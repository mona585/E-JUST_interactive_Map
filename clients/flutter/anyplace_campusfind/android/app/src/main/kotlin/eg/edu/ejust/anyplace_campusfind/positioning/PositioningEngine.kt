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
    val status: String,
    val bestDistance: Double = Double.POSITIVE_INFINITY,
    val topKSpreadMeters: Double = 0.0
)

/**
 * Thread-safe registry of resident RadioMaps.
 *
 * Multiple maps may be resident simultaneously, bounded by [RESIDENT_MAP_LIMIT]
 * with least-recently-used eviction. Each Wi-Fi scan is localized against every
 * resident map and exactly ONE estimate is dispatched, produced by the
 * measurement winner: highest matched AP count, ties broken by lowest RSS
 * distance to the closest fingerprint.
 *
 * Winner selection is measurement-only. Routes, destinations, selected POIs,
 * selected buildings and selected floors never participate here - UI selection
 * decides which maps are loaded into residency, never which map wins.
 */
object PositioningEngine {
    private const val TAG = "Positioning"

    /** Capacity of the resident-map set. Single native source of truth. */
    const val RESIDENT_MAP_LIMIT = 4

    /**
     * Access-ordered LRU keyed by "buid|floor". Only [loadRadioMapText],
     * [removeRadioMap] and [clearRadioMap] influence recency; localization runs
     * over iteration order and never reorders entries.
     */
    private val residentMaps = LinkedHashMap<String, RadioMap>(16, 0.75f, true)

    interface PositionUpdateListener {
        fun onPositionEstimated(estimate: NativePositionEstimate)
    }

    @Volatile
    private var listener: PositionUpdateListener? = null

    fun setListener(listener: PositionUpdateListener?) {
        this.listener = listener
    }

    /**
     * Clears the listener only when [listener] is still the registered one.
     *
     * During activity recreation the replacement bridge registers its listener
     * BEFORE the outgoing bridge's dispose runs; an unconditional clear here
     * would silently detach the new bridge and stop all estimate delivery.
     */
    fun clearListener(listener: PositionUpdateListener) {
        synchronized(this) {
            if (this.listener === listener) {
                this.listener = null
            }
        }
    }

    private fun keyOf(buid: String, floor: String): String = "$buid|$floor"

    /**
     * Atomically parses and upserts a RadioMap keyed by "buid|floor" (the upsert
     * refreshes recency). A rejected or invalid map leaves every existing
     * resident map - including any prior map under the same key - untouched.
     * Evicts the least-recently-used map only while the set exceeds
     * [RESIDENT_MAP_LIMIT].
     */
    @Synchronized
    fun loadRadioMapText(text: String, buid: String, floor: String): Boolean {
        return try {
            // Parse fully BEFORE touching resident state: every failure path
            // below leaves existing resident maps intact.
            val parsed = RadioMap(text = text, buid = buid, floor = floor)
            if (parsed.fingerprintCount == 0 || parsed.apCount == 0) {
                Log.w(TAG, "Rejected RadioMap for $buid/$floor: 0 APs or 0 fingerprints")
                return false
            }
            residentMaps[keyOf(buid, floor)] = parsed
            evictEldestIfNeeded()
            Log.d(
                TAG,
                "RadioMap upserted: $buid / floor $floor " +
                    "(${parsed.apCount} APs, ${parsed.fingerprintCount} fingerprints); " +
                    "resident=${residentMaps.size}"
            )
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse RadioMap for $buid/$floor: ${e.message}")
            false
        }
    }

    /** Targeted removal of one resident map. Returns true when it was present. */
    @Synchronized
    fun removeRadioMap(buid: String, floor: String): Boolean {
        val removed = residentMaps.remove(keyOf(buid, floor))
        if (removed != null) {
            Log.d(TAG, "RadioMap removed: $buid / floor $floor; resident=${residentMaps.size}")
        }
        return removed != null
    }

    /** Explicit global clear of the whole resident set. */
    @Synchronized
    fun clearRadioMap() {
        if (residentMaps.isNotEmpty()) {
            residentMaps.clear()
            Log.d(TAG, "All resident RadioMaps cleared")
        }
    }

    val hasResidentMaps: Boolean
        get() = synchronized(this) { residentMaps.isNotEmpty() }

    val residentCount: Int
        get() = synchronized(this) { residentMaps.size }

    fun residentKeys(): List<String> =
        synchronized(this) { ArrayList(residentMaps.keys) }

    /**
     * Channel-compatible info payload: the legacy keys describe the most
     * recently loaded resident map; residentCount/residentKeys are additive
     * metadata. Returns null only when nothing is resident.
     */
    @Synchronized
    fun getActiveInfo(): Map<String, Any>? {
        if (residentMaps.isEmpty()) return null
        val mostRecent = residentMaps.values.last()
        return linkedMapOf(
            "buid" to mostRecent.buid,
            "floor" to mostRecent.floor,
            "apCount" to mostRecent.apCount,
            "fingerprintCount" to mostRecent.fingerprintCount,
            "nanValue" to mostRecent.nanValue,
            "residentCount" to residentMaps.size,
            "residentKeys" to ArrayList(residentMaps.keys)
        )
    }

    private fun evictEldestIfNeeded() {
        while (residentMaps.size > RESIDENT_MAP_LIMIT) {
            val eldestKey = residentMaps.keys.iterator().next()
            val eldest = residentMaps.remove(eldestKey)
            if (eldest != null) {
                Log.d(TAG, "Evicted LRU RadioMap ${eldest.buid} / floor ${eldest.floor}")
            }
        }
    }

    /**
     * Localizes one scan against every resident map and emits the single
     * winning estimate. Maps with zero matched APs are skipped immediately;
     * among the remaining candidates the winner has the highest matchedAps,
     * tie-broken by lowest bestDistance.
     */
    @Synchronized
    fun processScanResults(scanResults: List<ScanRecord>): NativePositionEstimate? {
        if (residentMaps.isEmpty()) return null
        val startTime = System.currentTimeMillis()

        var winnerMap: RadioMap? = null
        var winnerResult: LocalizationResult? = null

        // Iterating values() does not mutate access order, so localization
        // never disturbs LRU recency.
        for (map in residentMaps.values) {
            val result = KnnLocalizer.localize(scanResults, map)
            if (result.matchedAps <= 0 || result.latLng == null) continue
            val current = winnerResult
            val better = current == null ||
                result.matchedAps > current.matchedAps ||
                (result.matchedAps == current.matchedAps && result.bestDistance < current.bestDistance)
            if (better) {
                winnerMap = map
                winnerResult = result
            }
        }

        val durationMs = System.currentTimeMillis() - startTime

        val estimate = if (winnerMap != null && winnerResult != null) {
            NativePositionEstimate(
                latitude = winnerResult.latLng?.latitude,
                longitude = winnerResult.latLng?.longitude,
                buid = winnerMap.buid,
                floor = winnerMap.floor,
                matchedAps = winnerResult.matchedAps,
                totalAps = winnerResult.totalAps,
                durationMs = durationMs,
                timestamp = System.currentTimeMillis(),
                status = "success",
                bestDistance = winnerResult.bestDistance,
                topKSpreadMeters = winnerResult.topKSpreadMeters
            )
        } else {
            // No evidence matched anywhere: emit no identity claim.
            NativePositionEstimate(
                latitude = null,
                longitude = null,
                buid = "",
                floor = "",
                matchedAps = 0,
                totalAps = scanResults.size,
                durationMs = durationMs,
                timestamp = System.currentTimeMillis(),
                status = "no_match"
            )
        }

        Log.d(
            TAG,
            "Scan: ${scanResults.size} APs seen across ${residentMaps.size} resident map(s), " +
                "winner=${estimate.buid}/floor ${estimate.floor}, " +
                "matched=${estimate.matchedAps}, ${durationMs}ms"
        )

        listener?.onPositionEstimated(estimate)
        return estimate
    }
}
