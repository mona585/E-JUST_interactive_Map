import org.specs2.mutable.Specification
import play.api.test._
import play.api.test.Helpers._
import play.api.libs.json.{Json, JsValue}
import play.api.mvc.Result
import scala.concurrent.Future
import java.io.ByteArrayInputStream
import java.util.zip.GZIPInputStream

class DatabaseBaselineSpec extends PlaySpecification {

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

  "Database Baseline & Hydration Contract" should {

    "assign admin role to the first user registered on empty system" in new WithApplication {
      val firstUserPayload = Json.obj(
        "name" -> "Test Admin User",
        "email" -> "admin@ejust.edu.eg",
        "username" -> "test_admin",
        "password" -> "AdminPassword123!"
      )
      val regReq = route(app, FakeRequest(POST, "/api/user/register").withJsonBody(firstUserPayload)).get
      status(regReq) must equalTo(OK)
      val json = extractJson(regReq)
      (json \ "status").asOpt[String] must beSome("success")
      (json \ "newUser" \ "type").asOpt[String] must beSome("admin")
    }

    "assign user role to subsequent user registered" in new WithApplication {
      val secondUserPayload = Json.obj(
        "name" -> "Test Ordinary User",
        "email" -> "student@ejust.edu.eg",
        "username" -> "test_student",
        "password" -> "StudentPassword123!"
      )
      val regReq = route(app, FakeRequest(POST, "/api/user/register").withJsonBody(secondUserPayload)).get
      status(regReq) must equalTo(OK)
      val json = extractJson(regReq)
      (json \ "status").asOpt[String] must beSome("success")
      (json \ "newUser" \ "type").asOpt[String] must beSome("user")
    }

    "return valid empty space contract on fresh/empty database" in new WithApplication {
      val spacesReq = route(app, FakeRequest(POST, "/api/mapping/space/public").withJsonBody(Json.obj())).get
      status(spacesReq) must equalTo(OK)
      val json = extractJson(spacesReq)
      (json \ "spaces").asOpt[Seq[JsValue]] must beSome
      (json \ "buildings").asOpt[Seq[JsValue]] must beSome
    }

  }
}
