import org.specs2.mutable.Specification
import play.api.Configuration
import play.api.libs.json.Json
import play.api.test.Helpers.stubControllerComponents
import utils.{AnyplaceServerAPI, FileUtils, FloorplanCache}

import java.io.ByteArrayInputStream
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.util.zip.GZIPInputStream

class FloorplanCacheSpec extends Specification {

  private val conf = Configuration(
    "public.baseUrl" -> "http://localhost:9000",
    "floorPlansRootDir" -> "/tmp/anyplace-floorplan-cache/floorplans",
    "radioMapFrozenDir" -> "/tmp/anyplace-floorplan-cache/radiomaps_frozen")
  private val api = new AnyplaceServerAPI(conf)
  private val files = new FileUtils(stubControllerComponents(), conf, api)

  private def write(path: java.nio.file.Path, content: String): java.io.File = {
    Files.write(path, content.getBytes(StandardCharsets.UTF_8))
    path.toFile
  }

  private def gunzip(bytes: Array[Byte]): String = {
    val in = new GZIPInputStream(new ByteArrayInputStream(bytes))
    try new String(in.readAllBytes(), StandardCharsets.UTF_8)
    finally in.close()
  }

  sequential

  "FloorplanCache" should {
    "cache the combined all-floors payload and invalidate it" in {
      FloorplanCache.clear()
      val dir = Files.createTempDirectory("anyplace-floorplan-cache")
      try {
        val f0 = write(dir.resolve("fl_0"), "floor-zero")
        val f1 = write(dir.resolve("fl_1"), "floor-one")
        val floors = Seq("0" -> f0, "1" -> f1)

        val first = FloorplanCache.getAllOrCompute("buid", floors, files)
        val second = FloorplanCache.getAllOrCompute("buid", floors, files)
        (second eq first) must beTrue

        val decoded = Json.parse(gunzip(first.gzippedBytes))
        (decoded \ "all_floors").as[List[String]] must haveSize(2)

        FloorplanCache.invalidate("buid", "0")
        val third = FloorplanCache.getAllOrCompute("buid", floors, files)
        (third eq first) must beFalse
      } finally {
        FloorplanCache.clear()
        Files.walk(dir).sorted(java.util.Comparator.reverseOrder())
          .forEach(p => Files.deleteIfExists(p))
      }
    }

    "refresh the combined payload when a floor changes" in {
      FloorplanCache.clear()
      val dir = Files.createTempDirectory("anyplace-floorplan-cache")
      try {
        val f0 = write(dir.resolve("fl_0"), "one")
        val f1 = write(dir.resolve("fl_1"), "two")
        val floors = Seq("0" -> f0, "1" -> f1)

        val first = FloorplanCache.getAllOrCompute("buid", floors, files)
        write(dir.resolve("fl_1"), "two-changed")
        val second = FloorplanCache.getAllOrCompute("buid", floors, files)
        (second eq first) must beFalse
        gunzip(second.gzippedBytes) must contain("dHdvLWNoYW5nZWQ=")
      } finally {
        FloorplanCache.clear()
        Files.walk(dir).sorted(java.util.Comparator.reverseOrder())
          .forEach(p => Files.deleteIfExists(p))
      }
    }
  }
}
