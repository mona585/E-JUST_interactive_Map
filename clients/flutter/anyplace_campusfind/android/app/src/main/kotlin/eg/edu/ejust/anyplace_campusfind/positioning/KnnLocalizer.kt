package eg.edu.ejust.anyplace_campusfind.positioning

import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

data class LatLng(val latitude: Double, val longitude: Double)

data class ScanRecord(val bssid: String, val rssi: Int)

data class LocDistance(val distance: Double, val lat: Double, val lon: Double)

/**
 * Result of one localization pass.
 *
 * The trailing evidence fields are purely observational and never influence
 * the computed [latLng]: [bestDistance] is the RSS-space distance of the
 * closest fingerprint ([Double.POSITIVE_INFINITY] when nothing was localized),
 * and [topKSpreadMeters] is the maximum pairwise great-circle distance among
 * the k selected fingerprint locations (0 when fewer than two were selected).
 */
data class LocalizationResult(
    val latLng: LatLng?,
    val matchedAps: Int,
    val totalAps: Int,
    val bestDistance: Double = Double.POSITIVE_INFINITY,
    val topKSpreadMeters: Double = 0.0
)

/**
 * Weighted K-Nearest-Neighbor (WKNN) fingerprint localization.
 *
 * Matches the observed scan RSS vector against every RadioMap fingerprint using
 * Euclidean distance over the shared MAC address space, then averages the k=4
 * closest fingerprints weighted by inverse distance.
 */
object KnnLocalizer {
    const val DEFAULT_K = 4

    private const val EARTH_RADIUS_METERS = 6371008.8

    fun localize(
        scanResults: List<ScanRecord>,
        radioMap: RadioMap,
        k: Int = DEFAULT_K,
        isWeighted: Boolean = true
    ): LocalizationResult {
        if (scanResults.isEmpty() || radioMap.fingerprintCount == 0) {
            return LocalizationResult(null, 0, scanResults.size)
        }

        val macList = radioMap.macAddressList
        val observedRss = DoubleArray(macList.size)
        var matchedAps = 0

        val scanMap = HashMap<String, Int>(scanResults.size)
        for (scan in scanResults) {
            if (scan.bssid.isNotEmpty()) scanMap[scan.bssid.lowercase()] = scan.rssi
        }

        for (i in macList.indices) {
            val rssi = scanMap[macList[i].lowercase()]
            if (rssi != null) {
                observedRss[i] = rssi.toDouble()
                matchedAps++
            } else {
                observedRss[i] = radioMap.nanValue
            }
        }

        if (matchedAps == 0) {
            return LocalizationResult(null, 0, scanResults.size)
        }

        val distances = ArrayList<LocDistance>(radioMap.locationRssMap.size)
        for ((locKey, storedRss) in radioMap.locationRssMap) {
            val coords = locKey.split(" ")
            if (coords.size < 2) continue
            val lat = coords[0].toDoubleOrNull() ?: continue
            val lon = coords[1].toDoubleOrNull() ?: continue

            var sumSquares = 0.0
            val size = minOf(storedRss.size, observedRss.size)
            for (i in 0 until size) {
                val diff = storedRss[i] - observedRss[i]
                sumSquares += diff.pow(2)
            }
            distances.add(LocDistance(sqrt(sumSquares), lat, lon))
        }

        if (distances.isEmpty()) {
            return LocalizationResult(null, matchedAps, scanResults.size)
        }

        distances.sortBy { it.distance }

        val actualK = minOf(k, distances.size)
        if (actualK <= 0) return LocalizationResult(null, matchedAps, scanResults.size)

        val estimate = if (isWeighted) {
            weightedAverage(distances, actualK)
        } else {
            unweightedAverage(distances, actualK)
        }

        return LocalizationResult(
            latLng = estimate,
            matchedAps = matchedAps,
            totalAps = scanResults.size,
            bestDistance = distances[0].distance,
            topKSpreadMeters = topKPairwiseSpreadMeters(distances, actualK)
        )
    }

    private fun unweightedAverage(distances: List<LocDistance>, k: Int): LatLng {
        var sumLat = 0.0
        var sumLon = 0.0
        for (i in 0 until k) {
            sumLat += distances[i].lat
            sumLon += distances[i].lon
        }
        return LatLng(sumLat / k, sumLon / k)
    }

    private fun weightedAverage(distances: List<LocDistance>, k: Int): LatLng {
        var sumWeights = 0.0
        var weightedLat = 0.0
        var weightedLon = 0.0

        for (i in 0 until k) {
            val dist = distances[i].distance
            val weight = if (dist == 0.0) 1000.0 else 1.0 / dist
            sumWeights += weight
            weightedLat += distances[i].lat * weight
            weightedLon += distances[i].lon * weight
        }

        return if (sumWeights > 0) {
            LatLng(weightedLat / sumWeights, weightedLon / sumWeights)
        } else {
            unweightedAverage(distances, k)
        }
    }

    private fun topKPairwiseSpreadMeters(distances: List<LocDistance>, k: Int): Double {
        var maxSpread = 0.0
        for (i in 0 until k) {
            for (j in i + 1 until k) {
                val d = distanceMeters(
                    distances[i].lat,
                    distances[i].lon,
                    distances[j].lat,
                    distances[j].lon
                )
                if (d > maxSpread) maxSpread = d
            }
        }
        return maxSpread
    }

    private fun distanceMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val halfChord = sin(dLat / 2).pow(2) +
            cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) * sin(dLon / 2).pow(2)
        return 2 * EARTH_RADIUS_METERS * atan2(sqrt(halfChord), sqrt(1 - halfChord))
    }
}
