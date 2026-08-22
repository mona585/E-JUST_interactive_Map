package eg.edu.ejust.anyplace_campusfind.positioning

import java.io.BufferedReader
import java.io.StringReader

/**
 * In-memory Anyplace RadioMap (mean RSS model).
 *
 * Plaintext format:
 * Line 1: `# NaN <nanValue>`                       e.g. `# NaN -110`
 * Line 2: `# X, Y, HEADING, <mac1>, <mac2>, ...`
 * Line 3+: `<lat>, <lon>, <heading>, <rss1>, <rss2>, ...`
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
        require(parse(text)) { "Invalid RadioMap plaintext format" }
    }

    private fun parse(rawText: String): Boolean {
        if (rawText.trim().isEmpty()) return false

        macAddressList.clear()
        locationRssMap.clear()
        orderList.clear()

        val reader = BufferedReader(StringReader(rawText))
        try {
            // Line 1: "# NaN -110"
            val line1 = reader.readLine() ?: return false
            val parts1 = line1.trim().split(Regex("\\s+"))
            if (parts1.size >= 3 && parts1[1].equals("NaN", ignoreCase = true)) {
                nanValue = parts1[2].toDoubleOrNull() ?: -110.0
            }

            // Line 2: header with MAC addresses
            val line2 = reader.readLine() ?: return false
            val headerTokens = line2.replace(",", " ").trim().split(Regex("\\s+"))
            if (headerTokens.size < 4) return false

            var macStart = if (headerTokens[0] == "#") 4 else 3
            for (i in macStart until headerTokens.size) {
                val mac = headerTokens[i].trim()
                if (mac.isNotEmpty()) macAddressList.add(mac)
            }
            if (macAddressList.isEmpty()) return false

            // Fingerprint lines
            while (true) {
                val line = reader.readLine() ?: break
                val trimmed = line.trim()
                if (trimmed.isEmpty() || trimmed.startsWith("#")) continue

                val tokens = trimmed.replace(",", " ").trim().split(Regex("\\s+"))
                if (tokens.size < 4) continue

                val lat = tokens[0].toDoubleOrNull() ?: continue
                val lon = tokens[1].toDoubleOrNull() ?: continue
                val key = "$lat $lon"

                val rssList = ArrayList<Double>(macAddressList.size)
                for (i in 3 until tokens.size) {
                    rssList.add(tokens[i].toDoubleOrNull() ?: nanValue)
                }
                while (rssList.size < macAddressList.size) {
                    rssList.add(nanValue)
                }

                locationRssMap[key] = rssList
                if (!orderList.contains(key)) orderList.add(key)
            }

            return orderList.isNotEmpty()
        } catch (e: Exception) {
            return false
        } finally {
            reader.close()
        }
    }
}
