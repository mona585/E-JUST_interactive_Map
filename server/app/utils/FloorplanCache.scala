package utils

import java.io.File
import java.util.{LinkedHashMap, Map => JMap}

case class CachedFloorplan(lastModified: Long, length: Long, base64: String, gzippedBytes: Array[Byte])

/**
 * Bounded, byte-aware LRU cache for encoded floorplans.
 *
 * Floorplan sources are multi-megabyte images; caching both their base64 form
 * and gzip output is memory-expensive. Entries are therefore bounded by total
 * bytes as well as by count, and the least recently used entry is evicted
 * first. Freshness is checked against the file's modification time and size.
 */
object FloorplanCache {
  private val MAX_ENTRIES = 24
  private val MAX_BYTES = 128L * 1024L * 1024L

  private class LruMap extends LinkedHashMap[String, CachedFloorplan](16, 0.75f, true)

  private val cache = new LruMap()
  private var totalBytes = 0L

  private def entryBytes(e: CachedFloorplan): Long =
    e.base64.length.toLong * 2L + e.gzippedBytes.length.toLong

  def getOrCompute(buid: String, floorNum: String, file: File, fu: FileUtils): CachedFloorplan = {
    val key = s"$buid:$floorNum"
    val lm = file.lastModified()
    val len = file.length()

    val fresh = cache.synchronized {
      val existing = cache.get(key)
      if (existing != null && existing.lastModified == lm && existing.length == len) existing else null
    }
    if (fresh != null) return fresh

    // Encode outside the lock: a multi-megabyte floorplan must not block
    // requests for other floors. Concurrent misses may duplicate one encode,
    // but the first completed entry wins and the duplicate is discarded.
    val base64 = Utils.encodeFileToBase64Binary(fu, file.getAbsolutePath)
    val gzipv = Utils.gzip(base64)
    val entry = CachedFloorplan(lm, len, base64, gzipv.toByteArray)

    cache.synchronized {
      val current = cache.get(key)
      if (current != null && current.lastModified == lm && current.length == len) {
        current
      } else {
        val previous = cache.put(key, entry)
        if (previous != null) totalBytes -= entryBytes(previous)
        totalBytes += entryBytes(entry)
        evict()
        entry
      }
    }
  }

  private def evict(): Unit = {
    val it = cache.entrySet().iterator()
    while ((cache.size() > MAX_ENTRIES || totalBytes > MAX_BYTES) && it.hasNext) {
      val e = it.next()
      totalBytes -= entryBytes(e.getValue)
      it.remove()
    }
  }

  def invalidate(buid: String, floorNum: String): Unit = cache.synchronized {
    val removed = cache.remove(s"$buid:$floorNum")
    if (removed != null) totalBytes -= entryBytes(removed)
  }

  def clear(): Unit = cache.synchronized {
    cache.clear()
    totalBytes = 0L
  }

  def size(): Int = cache.synchronized(cache.size())

  def bytes(): Long = cache.synchronized(totalBytes)
}
