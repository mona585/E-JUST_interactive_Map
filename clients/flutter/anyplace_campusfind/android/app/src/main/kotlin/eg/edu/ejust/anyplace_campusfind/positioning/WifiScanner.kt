package eg.edu.ejust.anyplace_campusfind.positioning

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.wifi.WifiManager
import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * Event-driven Wi-Fi scan manager.
 *
 * Primary trigger: [WifiManager.SCAN_RESULTS_AVAILABLE_ACTION] broadcast, which fires
 * whenever the system completes a Wi-Fi scan from ANY requester (this app, Google Play
 * services location scanning, other apps). This is not subject to this app's own scan
 * throttling quota.
 *
 * Fallback: a lazy re-trigger loop that calls [WifiManager.startScan] only when no scan
 * result has arrived within [FALLBACK_RETRIGGER_MS], so we never run a tight polling loop
 * and respect the platform throttle (~4 self-initiated scans / 2 min on API 28+).
 *
 * On start, cached system scan results are processed immediately so a valid position
 * estimate is available without waiting for a fresh scan.
 */
class WifiScanner(private val context: Context) {
    companion object {
        private const val TAG = "WifiScanner"

        /**
         * If no SCAN_RESULTS_AVAILABLE_ACTION arrives within this window (e.g. radio
         * idle with screen off, no other app scanning), re-request a scan. 10s keeps
         * estimates flowing while staying far below the throttling quota.
         */
        private const val FALLBACK_RETRIGGER_MS = 10_000L
    }

    private val wifiManager: WifiManager? =
        context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager

    private var isRunning = false
    private var receiverRegistered = false
    private var lastScanResultAt = 0L
    private val handler = Handler(Looper.getMainLooper())

    private val wifiScanReceiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context?, intent: Intent?) {
            if (intent?.action != WifiManager.SCAN_RESULTS_AVAILABLE_ACTION) return
            lastScanResultAt = System.currentTimeMillis()
            handleScanResults()
        }
    }

    private val fallbackRunnable = object : Runnable {
        override fun run() {
            if (!isRunning) return

            if (!PositioningEngine.hasActiveRadioMap) {
                Log.d(TAG, "No active RadioMap; stopping fallback loop")
                stopScanning()
                return
            }

            val sinceLast = System.currentTimeMillis() - lastScanResultAt
            if (sinceLast >= FALLBACK_RETRIGGER_MS) {
                try {
                    val started = wifiManager?.startScan() ?: false
                    Log.d(TAG, "Fallback startScan() after ${sinceLast}ms without results -> $started")
                } catch (e: Exception) {
                    Log.e(TAG, "startScan failed: ${e.message}")
                }
            }

            handler.postDelayed(this, FALLBACK_RETRIGGER_MS)
        }
    }

    @Synchronized
    fun startScanning() {
        if (isRunning) return
        isRunning = true
        Log.d(TAG, "Starting event-driven Wi-Fi scanning")

        try {
            if (!receiverRegistered) {
                context.applicationContext.registerReceiver(
                    wifiScanReceiver,
                    IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION)
                )
                receiverRegistered = true
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to register scan receiver: ${e.message}")
        }

        // Process whatever results the system already has: instant first fix.
        lastScanResultAt = System.currentTimeMillis()
        handler.post {
            if (isRunning) handleScanResults()
        }

        handler.postDelayed(fallbackRunnable, FALLBACK_RETRIGGER_MS)
    }

    @Synchronized
    fun stopScanning() {
        if (!isRunning) return
        isRunning = false
        Log.d(TAG, "Stopping Wi-Fi scanning")

        handler.removeCallbacks(fallbackRunnable)

        if (receiverRegistered) {
            try {
                context.applicationContext.unregisterReceiver(wifiScanReceiver)
            } catch (e: Exception) {
                Log.d(TAG, "Receiver already unregistered")
            }
            receiverRegistered = false
        }
    }

    private fun handleScanResults() {
        if (!isRunning || !PositioningEngine.hasActiveRadioMap) return

        val rawResults = try {
            wifiManager?.scanResults ?: emptyList()
        } catch (e: Exception) {
            Log.e(TAG, "Error reading scanResults: ${e.message}")
            emptyList()
        }

        val scanRecords = rawResults.mapNotNull { result ->
            val bssid = result.BSSID
            if (bssid.isNullOrEmpty()) null else ScanRecord(bssid, result.level)
        }

        PositioningEngine.processScanResults(scanRecords)
    }
}
