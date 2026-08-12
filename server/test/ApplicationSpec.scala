import org.specs2.mutable.Specification
import play.api.test._
import play.api.test.Helpers._
import play.api.mvc.Result

import java.io.ByteArrayInputStream
import java.util.zip.GZIPInputStream
import scala.concurrent.Future

class ApplicationSpec extends PlaySpecification {

  def extractString(result: Future[Result]): String = {
    val bytes = contentAsBytes(result).toArray
    if (bytes.length >= 2 && (bytes(0) & 0xFF) == 0x1f && (bytes(1) & 0xFF) == 0x8b) {
      val gis = new GZIPInputStream(new ByteArrayInputStream(bytes))
      scala.io.Source.fromInputStream(gis, "UTF-8").mkString
    } else {
      contentAsString(result)
    }
  }

  "Core public API" should {

    "redirect an unknown GET route to Viewer" in new WithApplication {
      val response = route(app, FakeRequest(GET, "/invalid-route-path")).get
      status(response) must equalTo(SEE_OTHER)
    }

    "return version JSON without authentication" in new WithApplication {
      val response = route(app, FakeRequest(GET, "/api/version")).get
      status(response) must equalTo(OK)
      extractString(response) must contain("version")
    }
  }
}
