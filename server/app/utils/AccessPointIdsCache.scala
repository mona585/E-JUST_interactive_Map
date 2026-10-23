package utils

import play.api.libs.json._

import java.io.InputStream

/**
 * In-memory vendor lookup for access-point MAC addresses.
 *
 * ids.json maps OUI prefixes (3 octets) to vendor names. The previous lookup
 * re-parsed the file and scanned it for every request; this cache parses once
 * and matches the longest available prefix.
 */
object AccessPointIdsCache {
  @volatile private var prefixMap: Map[String, String] = null
  private val lock = new Object()

  def getOrLoad(streamSupplier: () => InputStream): Map[String, String] = {
    if (prefixMap != null) return prefixMap
    lock.synchronized {
      if (prefixMap != null) return prefixMap
      val is = streamSupplier()
      if (is == null) return null
      try {
        val json = Json.parse(is).asOpt[List[JsObject]].getOrElse(List.empty)
        var map = Map[String, String]()
        for (entry <- json) {
          val mac = (entry \ "mac").asOpt[String].getOrElse("").trim.toUpperCase
          val id = (entry \ "id").asOpt[String].getOrElse("N/A")
          if (mac.nonEmpty && !map.contains(mac)) map += (mac -> id)
        }
        prefixMap = map
        prefixMap
      } finally {
        is.close()
      }
    }
  }

  def lookup(reqMacs: List[String], streamSupplier: () => InputStream): Option[List[String]] = {
    val map = getOrLoad(streamSupplier)
    if (map == null) return None
    Some(reqMacs.map { mac =>
      val parts = Option(mac).getOrElse("").trim.split(":").filter(_.nonEmpty)
      var foundId = "N/A"
      var length = math.min(parts.length, 6)
      var matched = false
      while (length >= 3 && !matched) {
        val cand = parts.take(length).map(_.toUpperCase).mkString(":")
        map.get(cand) match {
          case Some(id) => foundId = id; matched = true
          case None =>
        }
        length -= 1
      }
      foundId
    })
  }

  def clear(): Unit = lock.synchronized { prefixMap = null }
}
