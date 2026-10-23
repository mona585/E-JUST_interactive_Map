import org.specs2.mutable.Specification
import play.api.Configuration
import play.api.test.Helpers.stubControllerComponents
import utils.{AnyPlaceTilerHelper, AnyplaceServerAPI, FileUtils, Utils}

import java.nio.file.Files

class PathSafetySpec extends Specification {

  "Utils path guards" should {

    "accept ordinary path segments" in {
      Utils.isSafePathSegment("buid_123") must beTrue
      Utils.isSafePathSegment("0") must beTrue
      Utils.isSafePathSegment("floor-1") must beTrue
    }

    "reject traversal, separators, empty and hidden segments" in {
      for (value <- Seq(null, "", ".", "..", "../etc", "a/b", "a\\b", "a" + 0.toChar + "b", ".hidden")) {
        Utils.isSafePathSegment(value) must beFalse
      }
      ok
    }

    "accept relative tile paths and reject escaping paths" in {
      Utils.isSafeRelativePath("0/1/2.png") must beTrue
      Utils.isSafeRelativePath("tiles_archive.zip") must beTrue
      for (value <- Seq(null, "", "/etc/passwd", "../etc", "0/../../etc", "0\\..\\etc")) {
        Utils.isSafeRelativePath(value) must beFalse
      }
      ok
    }

    "keep canonical paths inside the configured root" in {
      val root = Files.createTempDirectory("anyplace-path-root")
      try {
        val inside = root.resolve("buid").resolve("floor")
        Utils.isWithinRoot(root.toString, inside.toString) must beTrue
        Utils.isWithinRoot(root.toString, root.resolve("..").resolve("escape").toString) must beFalse
      } finally {
        Files.deleteIfExists(root)
      }
    }
  }

  "Filesystem path builders" should {

    val conf = Configuration(
      "public.baseUrl" -> "http://localhost:9000",
      "floorPlansRootDir" -> "/tmp/anyplace-path-safety/floorplans",
      "radioMapFrozenDir" -> "/tmp/anyplace-path-safety/radiomaps_frozen")
    val api = new AnyplaceServerAPI(conf)
    val tiler = new AnyPlaceTilerHelper(stubControllerComponents(), conf, api)
    val files = new FileUtils(stubControllerComponents(), conf, api)

    "build normal floorplan and radiomap paths" in {
      tiler.getFloorPlanFor("buid_123", "0") must
        equalTo("/tmp/anyplace-path-safety/floorplans/buid_123/fl_0/fl_0")
      files.getDirFrozenFloor("buid_123", "0").getPath must
        equalTo("/tmp/anyplace-path-safety/radiomaps_frozen/buid_123/0")
    }

    "reject traversal in tiler identifiers" in {
      for (value <- Seq("..", "../etc", "a/b", "a\\b", "")) {
        tiler.getFloorPlanFor(value, "0") must throwA[IllegalArgumentException]
        tiler.getFloorPlanFor("buid_123", value) must throwA[IllegalArgumentException]
      }
      ok
    }

    "reject traversal in frozen radiomap identifiers" in {
      for (value <- Seq("..", "../etc", "a/b", "a\\b", "")) {
        files.getDirFrozenFloor(value, "0") must throwA[IllegalArgumentException]
        files.getDirFrozenFloor("buid_123", value) must throwA[IllegalArgumentException]
      }
      ok
    }
  }
}
