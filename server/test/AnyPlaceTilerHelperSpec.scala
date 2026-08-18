import org.specs2.mutable.Specification
import play.api.Configuration
import play.api.test.Helpers.stubControllerComponents
import utils.{AnyPlaceTilerHelper, AnyplaceServerAPI}

/**
 * Regression test for R-10 (Phase 6): the generated floor-tiles archive
 * link must use "/" and the live `/api/floortiles/...` route, not the
 * host OS path separator or the legacy `/anyplace/floortiles` prefix.
 * Does not require MongoDB or a running Play application.
 */
class AnyPlaceTilerHelperSpec extends Specification {

  val conf: Configuration = Configuration.from(Map(
    "server.address" -> "https://map.ejust.edu.eg",
    "server.port" -> "443",
    "tilerRootDir" -> "anyplace_tiler",
    "floorPlansRootDir" -> "floorplans"
  ))
  val api = new AnyplaceServerAPI(conf)
  val helper = new AnyPlaceTilerHelper(stubControllerComponents(), conf, api)

  "AnyPlaceTilerHelper.getFloorTilesZipLinkFor" should {

    "build the live /api/floortiles URL with '/' separators" in {
      helper.getFloorTilesZipLinkFor("building_1", "0") must
        equalTo("https://map.ejust.edu.eg:443/api/floortiles/building_1/0/tiles_archive.zip")
    }

    "never contain a backslash regardless of host OS" in {
      helper.getFloorTilesZipLinkFor("building_1", "0") must not(contain("\\"))
    }

    "never use the legacy /anyplace/floortiles prefix" in {
      helper.getFloorTilesZipLinkFor("building_1", "0") must not(contain("anyplace/floortiles"))
    }

    "return null for blank buid or floor" in {
      helper.getFloorTilesZipLinkFor("", "0") must beNull
      helper.getFloorTilesZipLinkFor("building_1", "") must beNull
    }
  }
}
