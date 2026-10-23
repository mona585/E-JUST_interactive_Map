package utils

import java.util.{HashMap, LinkedHashMap, List => JList}

/**
 * Short-lived cache of the POI/edge snapshots used by indoor and campus
 * routing. A route request previously rebuilt these lists from Mongo every
 * time; the graph itself is still rebuilt per request so Dijkstra stays
 * isolated. Entries expire after 30s and are explicitly cleared on writes.
 */
object NavigationDataCache {

  final case class Entry(createdAt: Long,
                         pois: JList[HashMap[String, String]],
                         edges: JList[HashMap[String, String]])

  private val TTL_MILLIS = 30_000L
  private val MAX_ENTRIES = 16

  private val cache = new LinkedHashMap[String, Entry](16, 0.75f, true)

  def get(key: String): Option[Entry] = synchronized {
    val entry = cache.get(key)
    if (entry == null) None
    else if (System.currentTimeMillis() - entry.createdAt > TTL_MILLIS) {
      cache.remove(key)
      None
    } else Some(entry)
  }

  def put(key: String, entry: Entry): Unit = synchronized {
    cache.put(key, entry)
    evict()
  }

  /** Load outside the lock so one slow query cannot stall unrelated routes. */
  def getOrLoad(key: String)(load: => (JList[HashMap[String, String]], JList[HashMap[String, String]])): Entry =
    get(key).getOrElse {
      val (pois, edges) = load
      val entry = Entry(System.currentTimeMillis(), pois, edges)
      put(key, entry)
      entry
    }

  def floorKey(buid: String, floor: String): String = "floor|" + buid + "|" + floor

  def buildingKey(buid: String): String = "building|" + buid

  def campusKey(buids: List[String]): String = "campus|" + buids.sorted.mkString(",")

  def clear(): Unit = synchronized(cache.clear())

  def size(): Int = synchronized(cache.size())

  private def evict(): Unit = {
    while (cache.size() > MAX_ENTRIES) {
      val it = cache.keySet().iterator()
      if (it.hasNext) {
        it.next()
        it.remove()
      } else return
    }
  }
}
