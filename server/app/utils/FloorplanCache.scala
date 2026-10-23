package utils

import java.io.File
import java.util.{LinkedHashMap, Map => JMap}

case class CachedFloorplan(lastModified: Long, length: Long, base64: String, gzippedBytes: Array[Byte])

case class CachedFloorplanSet(lastModifieds: Vector[Long], lengths: Vector[Long], gzippedBytes: Array[Byte])

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
  private val MAX_SETS = 8
  private val MAX_SET_BYTES = 64L * 1024L * 1024L

  private class LruMap extends LinkedHashMap[String, CachedFloorplan](16, 0.75f, true)

  private val cache = new LruMap()
  private var totalBytes = 0L

  private class LruSetMap extends LinkedHashMap[String, CachedFloorplanSet](16, 0.75f, true)

  private val allCache = new LruSetMap()
  private var allBytes = 0L

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

  /**
   * Cache the complete `{"all_floors":[...]}` gzip payload for one building's
   * floor set. Viewers request this on every session; rebuilding the JSON and
   * gzipping tens of megabytes each time is otherwise pure repeated work.
   */
  def getAllOrCompute(buid: String, floors: Seq[(String, File)], fu: FileUtils): CachedFloorplanSet = {
    val key = buid + "|" + floors.map(_._1).mkString(" ")
    val stats = floors.map(_._2)
    val lastModifieds = stats.map(_.lastModified()).toVector
    val lengths = stats.map(_.length()).toVector

    val fresh = allCache.synchronized {
      val existing = allCache.get(key)
      if (existing != null && existing.lastModifieds == lastModifieds && existing.lengths == lengths) existing
      else null
    }
    if (fresh != null) return fresh

    val encoded = floors.map { case (floorNum, file) => getOrCompute(buid, floorNum, file, fu).base64 }
    val sb = new StringBuilder(encoded.foldLeft(32L)((n, b) => n + b.length + 3L).toInt)
    sb.append("{\"all_floors\":[")
    var i = 0
    while (i < encoded.length) {
      if (i > 0) sb.append(',')
      sb.append('"').append(encoded(i)).append('"')
      i += 1
    }
    sb.append("]}")
    val gzipv = Utils.gzip(sb.toString).toByteArray
    val entry = CachedFloorplanSet(lastModifieds, lengths, gzipv)

    allCache.synchronized {
      val current = allCache.get(key)
      if (current != null && current.lastModifieds == lastModifieds && current.lengths == lengths) {
        current
      } else {
        val previous = allCache.put(key, entry)
        if (previous != null) allBytes -= previous.gzippedBytes.length
        allBytes += entry.gzippedBytes.length
        evictSets()
        entry
      }
    }
  }

  private def evictSets(): Unit = {
    val it = allCache.entrySet().iterator()
    while ((allCache.size() > MAX_SETS || allBytes > MAX_SET_BYTES) && it.hasNext) {
      val e = it.next()
      allBytes -= e.getValue.gzippedBytes.length
      it.remove()
    }
  }

  def invalidate(buid: String, floorNum: String): Unit = {
    cache.synchronized {
      val removed = cache.remove(s"$buid:$floorNum")
      if (removed != null) totalBytes -= entryBytes(removed)
    }
    allCache.synchronized {
      val prefix = buid + "|"
      val it = allCache.entrySet().iterator()
      while (it.hasNext) {
        val e = it.next()
        if (e.getKey.startsWith(prefix)) {
          allBytes -= e.getValue.gzippedBytes.length
          it.remove()
        }
      }
    }
  }

  def clear(): Unit = {
    cache.synchronized {
      cache.clear()
      totalBytes = 0L
    }
    allCache.synchronized {
      allCache.clear()
      allBytes = 0L
    }
  }

  def size(): Int = cache.synchronized(cache.size())

  def bytes(): Long = cache.synchronized(totalBytes)
}
