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
 * Manages Android WifiManager scans and dispatches results to PositioningEngine.
 */
class WifiScanner(private val context: Context) {
    companion object {
        private const val TAG = "WifiScanner"
        private const val SCAN_INTERVAL_MS = 3000L
    }

    private val wifiManager: WifiManager? =
        context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager

    private var isScanning = false
    private val handler = Handler(Looper.getMainLooper())

    private val wifiScanReceiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context?, intent: Intent?) {
            if (intent?.action == WifiManager.SCAN_RESULTS_AVAILABLE_ACTION) {
                val success = intent.getBooleanExtra(WifiManager.EXTRA_RESULTS_UPDATED, false)
                Log.d(TAG, "Wi-Fi scan results received (success=$success)")
                handleScanResults()
            }
        }
    }

    private val scanRunnable = object : Runnable {
        override fun run() {
            if (!isScanning) return

            if (PositioningEngine.hasActiveRadioMap) {
                try {
                    val started = wifiManager?.startScan() ?: false
                    Log.d(TAG, "Triggered wifiManager.startScan() -> $started")
                } catch (e: Exception) {
                    Log.e(TAG, "Error starting Wi-Fi scan: ${e.message}")
                }
                handler.postDelayed(this, SCAN_INTERVAL_MS)
            } else {
                Log.d(TAG, "No active RadioMap; pausing scan loop")
                stopScanning()
            }
        }
    }

    @Synchronized
    fun startScanning() {
        if (isScanning) return
        isScanning = true
        Log.d(TAG, "Starting Wi-Fi scan loop")

        try {
            val filter = IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION)
            context.applicationContext.registerReceiver(wifiScanReceiver, filter)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to register BroadcastReceiver: ${e.message}")
        }

        handler.post(scanRunnable)
    }

    @Synchronized
    fun stopScanning() {
        if (!isScanning) return
        isScanning = false
        Log.d(TAG, "Stopping Wi-Fi scan loop")

        handler.removeCallbacks(scanRunnable)

        try {
            context.applicationContext.unregisterReceiver(wifiScanReceiver)
        } catch (e: Exception) {
            Log.d(TAG, "BroadcastReceiver was not registered or already unregistered")
        }
    }

    private fun handleScanResults() {
        val rawResults = try {
            wifiManager?.scanResults ?: emptyList()
        } catch (e: Exception) {
            Log.e(TAG, "Error reading scanResults: ${e.message}")
            emptyList()
        }

        val scanRecords = rawResults.map { result ->
            ScanRecord(
                bssid = result.BSSID ?: "",
                rssi = result.level
            )
        }.filter { it.bssid.isNotEmpty() }

        PositioningEngine.processScanResults(scanRecords)
    }
}
