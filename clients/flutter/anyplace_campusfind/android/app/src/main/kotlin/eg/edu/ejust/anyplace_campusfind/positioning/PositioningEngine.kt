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
 * Thread-safe holder of the active RadioMap; runs WKNN localization on each Wi-Fi
 * scan and dispatches estimates to the registered listener (PositioningBridge).
 */
object PositioningEngine {
    private const val TAG = "Positioning"

    @Volatile
    private var activeRadioMap: RadioMap? = null

    interface PositionUpdateListener {
        fun onPositionEstimated(estimate: NativePositionEstimate)
    }

    @Volatile
    private var listener: PositionUpdateListener? = null

    fun setListener(listener: PositionUpdateListener?) {
        this.listener = listener
    }

    /**
     * Atomically parses and loads a RadioMap. A rejected (invalid) map leaves the
     * previously active map untouched.
     */
    @Synchronized
    fun loadRadioMapText(text: String, buid: String, floor: String): Boolean {
        return try {
            val parsed = RadioMap(text = text, buid = buid, floor = floor)
            if (parsed.fingerprintCount > 0 && parsed.apCount > 0) {
                activeRadioMap = parsed
                Log.d(TAG, "RadioMap loaded: $buid / floor $floor (${parsed.apCount} APs, ${parsed.fingerprintCount} fingerprints)")
                true
            } else {
                Log.w(TAG, "Rejected RadioMap for $buid/$floor: 0 APs or 0 fingerprints")
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse RadioMap for $buid/$floor: ${e.message}")
            false
        }
    }

    @Synchronized
    fun clearRadioMap() {
        activeRadioMap = null
        Log.d(TAG, "Active RadioMap cleared")
    }

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

    val hasActiveRadioMap: Boolean
        get() = activeRadioMap != null

    fun processScanResults(scanResults: List<ScanRecord>): NativePositionEstimate? {
        val map = activeRadioMap ?: return null
        val startTime = System.currentTimeMillis()

        val result = KnnLocalizer.localize(scanResults, map)
        val durationMs = System.currentTimeMillis() - startTime
        val status = if (result.latLng != null) "success" else "no_match"

        Log.d(
            TAG,
            "Scan: ${scanResults.size} APs seen, ${result.matchedAps} matched, " +
                "estimate=${result.latLng}, ${durationMs}ms"
        )

        val estimate = NativePositionEstimate(
            latitude = result.latLng?.latitude,
            longitude = result.latLng?.longitude,
            buid = map.buid,
            floor = map.floor,
            matchedAps = result.matchedAps,
            totalAps = result.totalAps,
            durationMs = durationMs,
            timestamp = System.currentTimeMillis(),
            status = status
        )

        listener?.onPositionEstimated(estimate)
        return estimate
    }
}
