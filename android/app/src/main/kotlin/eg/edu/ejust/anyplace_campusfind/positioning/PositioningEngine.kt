package eg.edu.ejust.anyplace_campusfind.positioning

import android.util.Log

data class NativePositionEstimate(
    val latitude: Double?,
    val longitude: Double?,
    val buid: String,
    val floor: String,
    val matchedAps: Int,
    val totalAps: Int,
    val durationMs: Long,
    val timestamp: Long,
    val status: String
)

/**
 * Thread-safe engine managing active RadioMap and indoor positioning estimation.
 */
object PositioningEngine {
    private const val TAG = "Positioning"

    @Volatile
    private var activeRadioMap: RadioMap? = null

    /**
     * Listener interface for native position updates.
     */
    interface PositionUpdateListener {
        fun onPositionEstimated(estimate: NativePositionEstimate)
    }

    private var listener: PositionUpdateListener? = null

    fun setListener(listener: PositionUpdateListener?) {
        this.listener = listener
    }

    /**
     * Atomically parses and loads a new RadioMap plaintext.
     *
     * If the new text is valid, it replaces the active RadioMap and returns true.
     * If the new text is invalid or corrupted, it is rejected, the previous valid
     * RadioMap remains active, and it returns false.
     */
    @Synchronized
    fun loadRadioMapText(text: String, buid: String, floor: String): Boolean {
        return try {
            val parsed = RadioMap(text = text, buid = buid, floor = floor)
            if (parsed.fingerprintCount > 0 && parsed.apCount > 0) {
                activeRadioMap = parsed
                Log.d(
                    TAG,
                    "RadioMap loaded: $buid / floor $floor (${parsed.apCount} APs, ${parsed.fingerprintCount} fingerprints)"
                )
                true
            } else {
                Log.w(TAG, "Rejected RadioMap for buid=$buid, floor=$floor: 0 APs or 0 fingerprints")
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse RadioMap text for buid=$buid, floor=$floor: ${e.message}")
            false
        }
    }

    /**
     * Clears the currently active RadioMap.
     */
    @Synchronized
    fun clearRadioMap() {
        Log.d(TAG, "Clearing active RadioMap")
        activeRadioMap = null
    }

    /**
     * Returns metadata about the currently active RadioMap, or null if none is active.
     */
    @Synchronized
    fun getActiveInfo(): Map<String, Any>? {
        val map = activeRadioMap ?: return null
        return mapOf(
            "buid" to map.buid,
            "floor" to map.floor,
            "apCount" to map.apCount,
            "fingerprintCount" to map.fingerprintCount,
            "nanValue" to map.nanValue
        )
    }

    /**
     * Returns whether a valid RadioMap is currently loaded.
     */
    val hasActiveRadioMap: Boolean
        get() = activeRadioMap != null

    /**
     * Estimates WGS84 location from Wi-Fi scan results.
     */
    fun estimateLocation(scanResults: List<ScanRecord>): LatLng? {
        val map = activeRadioMap ?: return null
        return KnnLocalizer.estimateLocation(scanResults, map)
    }

    /**
     * Process Wi-Fi scan results, logs diagnostic metrics, and dispatches position estimate.
     */
    fun processScanResults(scanResults: List<ScanRecord>): NativePositionEstimate? {
        val map = activeRadioMap ?: return null
        val startTime = System.currentTimeMillis()

        Log.d(TAG, "WiFi scan: ${scanResults.size} APs")
        Log.d(TAG, "RadioMap: ${map.buid} / floor ${map.floor}")

        val result = KnnLocalizer.localize(scanResults, map)
        val duration = System.currentTimeMillis() - startTime

        Log.d(TAG, "Matched APs: ${result.matchedAps}")

        val status = if (result.latLng != null) "success" else "no_match"
        if (result.latLng != null) {
            Log.d(TAG, "KNN estimate: lat=${result.latLng.latitude}, lon=${result.latLng.longitude}")
        } else {
            Log.d(TAG, "KNN estimate: no match or insufficient AP data")
        }
        Log.d(TAG, "Localization: $duration ms")

        val estimate = NativePositionEstimate(
            latitude = result.latLng?.latitude,
            longitude = result.latLng?.longitude,
            buid = map.buid,
            floor = map.floor,
            matchedAps = result.matchedAps,
            totalAps = result.totalAps,
            durationMs = duration,
            timestamp = System.currentTimeMillis(),
            status = status
        )

        listener?.onPositionEstimated(estimate)
        return estimate
    }
}
