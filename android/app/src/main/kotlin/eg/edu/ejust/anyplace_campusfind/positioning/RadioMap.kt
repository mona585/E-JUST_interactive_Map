package eg.edu.ejust.anyplace_campusfind.positioning

import java.io.BufferedReader
import java.io.StringReader

/**
 * Parses and holds an in-memory Anyplace RadioMap mean model.
 *
 * Plain text format specification:
 * Line 1: `# NaN <nanValue>` (e.g. `# NaN -110`)
 * Line 2: `# X, Y, HEADING, <mac1>, <mac2>, <mac3>, ...`
 * Line 3+: `<lat>, <lon>, <heading>, <rss1>, <rss2>, <rss3>, ...`
 */
class RadioMap(
    val text: String,
    val buid: String = "",
    val floor: String = ""
) {
    var nanValue: Double = -110.0
        private set

    val macAddressList: ArrayList<String> = ArrayList()
    val locationRssMap: HashMap<String, ArrayList<Double>> = HashMap()
    val orderList: ArrayList<String> = ArrayList()

    val apCount: Int
        get() = macAddressList.size

    val fingerprintCount: Int
        get() = orderList.size

    init {
        if (!parse(text)) {
            throw IllegalArgumentException("Invalid RadioMap plaintext format")
        }
    }

    private fun parse(rawText: String): Boolean {
        if (rawText.trim().isEmpty()) {
            return false
        }

        macAddressList.clear()
        locationRssMap.clear()
        orderList.clear()

        val reader = BufferedReader(StringReader(rawText))
        try {
            // Line 1: # NaN -110
            val line1: String = reader.readLine() ?: return false
            val parts1 = line1.trim().split(Regex("\\s+"))
            if (parts1.size >= 3 && parts1[1].equals("NaN", ignoreCase = true)) {
                nanValue = parts1[2].toDoubleOrNull() ?: -110.0
            } else {
                nanValue = -110.0
            }

            // Line 2: # X, Y, HEADING, mac1, mac2, ...
            val line2: String = reader.readLine() ?: return false
            val cleanHeader = line2.replace(",", " ")
            val headerTokens = cleanHeader.trim().split(Regex("\\s+"))

            // Starts at index 4 (0: '#', 1: 'X', 2: 'Y', 3: 'HEADING', 4+: MAC addresses)
            var startOfRss = 4
            if (headerTokens.size < 4) {
                return false
            }
            if (headerTokens[0] != "#") {
                startOfRss = 3
            }

            for (i in startOfRss until headerTokens.size) {
                val mac = headerTokens[i].trim()
                if (mac.isNotEmpty()) {
                    macAddressList.add(mac)
                }
            }

            if (macAddressList.isEmpty()) {
                return false
            }

            // Fingerprint lines
            var currentLine: String?
            while (true) {
                currentLine = reader.readLine()
                if (currentLine == null) break
                val trimmed = currentLine.trim()
                if (trimmed.isEmpty() || trimmed.startsWith("#")) {
                    continue
                }

                val cleanLine = trimmed.replace(",", " ")
                val tokens = cleanLine.trim().split(Regex("\\s+"))

                if (tokens.size < 3) {
                    continue
                }

                val lat = tokens[0].toDoubleOrNull() ?: continue
                val lon = tokens[1].toDoubleOrNull() ?: continue
                val key = "$lat $lon"

                val rssList = ArrayList<Double>()
                // Starting from index 3 (after lat, lon, heading)
                val rssStartIndex = 3
                for (i in rssStartIndex until tokens.size) {
                    val rssVal = tokens[i].toDoubleOrNull() ?: nanValue
                    rssList.add(rssVal)
                }

                // Check that RSS values count matches or pads to MAC address count
                while (rssList.size < macAddressList.size) {
                    rssList.add(nanValue)
                }

                locationRssMap[key] = rssList
                if (!orderList.contains(key)) {
                    orderList.add(key)
                }
            }

            return orderList.isNotEmpty()
        } catch (e: Exception) {
            return false
        } finally {
            reader.close()
        }
    }
}
