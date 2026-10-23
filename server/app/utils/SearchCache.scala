package utils

import play.api.libs.json.JsValue

import java.util.LinkedHashMap

/**
 * Short-lived cache for public POI searches.
 *
 * Search runs a case-insensitive regex over the building's POIs, so repeated
 * keystrokes for the same query are pure duplicate work. Entries are bounded
 * and expire quickly; writes clear the cache explicitly.
 */
object SearchCache {
  private val MAX_ENTRIES = 64
  private val TTL_MILLIS = 30L * 1000L

  private case class Entry(createdAt: Long, results: List[JsValue])

  private class LruMap extends LinkedHashMap[String, Entry](16, 0.75f, true)

  private val cache = new LruMap()

  def get(key: String): Option[List[JsValue]] = cache.synchronized {
    val entry = cache.get(key)
    if (entry == null) None
    else if (System.currentTimeMillis() - entry.createdAt > TTL_MILLIS) {
      cache.remove(key)
      None
    } else Some(entry.results)
  }

  def put(key: String, results: List[JsValue]): Unit = cache.synchronized {
    cache.put(key, Entry(System.currentTimeMillis(), results))
    val it = cache.entrySet().iterator()
    while (cache.size() > MAX_ENTRIES && it.hasNext) {
      it.next()
      it.remove()
    }
  }

  def clear(): Unit = cache.synchronized(cache.clear())

  def size(): Int = cache.synchronized(cache.size())
}
