import org.specs2.mutable.Specification
import play.api.test._
import play.api.test.Helpers._
import play.api.libs.json.{Json, JsValue}
import play.api.mvc.Result
import play.api.Configuration
import utils.AnyplaceServerAPI
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

  def extractJson(result: Future[Result]): JsValue = {
    Json.parse(extractString(result))
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

    "return spaces array on public endpoint" in new WithApplication {
      val response = route(app, FakeRequest(POST, "/api/mapping/space/public").withJsonBody(Json.obj())).get
      status(response) must equalTo(OK)
      val json = extractJson(response)
      (json \ "spaces").asOpt[Seq[JsValue]] must beSome
    }

    "reject unauthenticated space co-owner and access requests" in new WithApplication {
      val coOwners = route(app, FakeRequest(POST, "/api/auth/mapping/space/coowners").withJsonBody(Json.obj())).get
      val access = route(app, FakeRequest(POST, "/api/auth/mapping/space/access").withJsonBody(Json.obj())).get
      status(coOwners) must beOneOf(UNAUTHORIZED, BAD_REQUEST, FORBIDDEN)
      status(access) must beOneOf(UNAUTHORIZED, BAD_REQUEST, FORBIDDEN)
    }

    "build public API URLs from public.baseUrl" in {
      val api = new AnyplaceServerAPI(Configuration("public.baseUrl" -> "https://staging.example.edu/"))
      api.SERVER_FULL_URL must equalTo("https://staging.example.edu")
      api.SERVER_PORT must equalTo("443")
      api.urlPath("api", "floortiles", "building_1", "0", "tiles_archive.zip") must
        equalTo("https://staging.example.edu/api/floortiles/building_1/0/tiles_archive.zip")
    }
  }
}
