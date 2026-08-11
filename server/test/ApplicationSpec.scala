import org.specs2.mutable.Specification
import play.api.test._
import play.api.test.Helpers._
import play.api.libs.json.{Json, JsValue}
import play.api.mvc.Result
import scala.concurrent.Future
import java.io.ByteArrayInputStream
import java.util.zip.GZIPInputStream

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

  def extractJson(result: Future[Result]): JsValue = {
    Json.parse(extractString(result))
  }

  "Application" should {

    "redirect non-existing GET route to viewer" in new WithApplication {
      val badRequest = route(app, FakeRequest(GET, "/invalid-route-path")).get
      status(badRequest) must equalTo(SEE_OTHER)
    }

    "return HTTP 200 and version JSON on /api/version" in new WithApplication {
      val versionReq = route(app, FakeRequest(GET, "/api/version")).get
      status(versionReq) must equalTo(OK)
      extractString(versionReq) must contain("version")
    }

    "return HTTP 200 and spaces array on /api/mapping/space/public" in new WithApplication {
      val spacesReq = route(app, FakeRequest(POST, "/api/mapping/space/public").withJsonBody(Json.obj())).get
      status(spacesReq) must equalTo(OK)
      val json = extractJson(spacesReq)
      (json \ "spaces").asOpt[Seq[JsValue]] must beSome
    }

  }
}
