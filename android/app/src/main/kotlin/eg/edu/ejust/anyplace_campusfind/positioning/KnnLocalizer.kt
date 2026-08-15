package eg.edu.ejust.anyplace_campusfind.positioning

import kotlin.math.pow
import kotlin.math.sqrt

data class LatLng(val latitude: Double, val longitude: Double)

data class ScanRecord(val bssid: String, val rssi: Int)

data class LocDistance(val distance: Double, val lat: Double, val lon: Double)

/**
 * K-Nearest Neighbor (KNN / WKNN) localization algorithm matching Anyplace reference implementation.
 */
object KnnLocalizer {
    const val DEFAULT_K = 4

    /**
     * Estimates user position given observed Wi-Fi scan results and active RadioMap.
     */
    fun estimateLocation(
        scanResults: List<ScanRecord>,
        radioMap: RadioMap,
        k: Int = DEFAULT_K,
        isWeighted: Boolean = true
    ): LatLng? {
        if (scanResults.isEmpty() || radioMap.fingerprintCount == 0) {
            return null
        }

        val macList = radioMap.macAddressList
        val observedRssValues = DoubleArray(macList.size)
        var matchedAps = 0

        // Map scanned BSSID to signal level
        val scanMap = HashMap<String, Int>()
        for (scan in scanResults) {
            scanMap[scan.bssid.lowercase()] = scan.rssi
        }

        for (i in macList.indices) {
            val mac = macList[i].lowercase()
            val rssi = scanMap[mac]
            if (rssi != null) {
                observedRssValues[i] = rssi.toDouble()
                matchedAps++
            } else {
                observedRssValues[i] = radioMap.nanValue
            }
        }

        // If no APs matched the radio map, localization cannot be performed
        if (matchedAps == 0) {
            return null
        }

        val distances = ArrayList<LocDistance>()

        for ((locKey, storedRss) in radioMap.locationRssMap) {
            val coords = locKey.split(" ")
            if (coords.size < 2) continue
            val lat = coords[0].toDoubleOrNull() ?: continue
            val lon = coords[1].toDoubleOrNull() ?: continue

            var sumSquares = 0.0
            val size = minOf(storedRss.size, observedRssValues.size)
            for (i in 0 until size) {
                val diff = storedRss[i] - observedRssValues[i]
                sumSquares += diff.pow(2)
            }
            val dist = sqrt(sumSquares)
            distances.add(LocDistance(dist, lat, lon))
        }

        if (distances.isEmpty()) {
            return null
        }

        // Sort by distance ascending (closest first)
        distances.sortBy { it.distance }

        val actualK = minOf(k, distances.size)
        if (actualK <= 0) return null

        return if (isWeighted) {
            calculateWeightedK(distances, actualK)
        } else {
            calculateUnweightedK(distances, actualK)
        }
    }

    private fun calculateUnweightedK(distances: List<LocDistance>, k: Int): LatLng {
        var sumLat = 0.0
        var sumLon = 0.0
        for (i in 0 until k) {
            sumLat += distances[i].lat
            sumLon += distances[i].lon
        }
        return LatLng(sumLat / k, sumLon / k)
    }

    private fun calculateWeightedK(distances: List<LocDistance>, k: Int): LatLng {
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
            calculateUnweightedK(distances, k)
        }
    }
}
