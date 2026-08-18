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

  /**
   * Generate a unique tag so each test run produces distinct user email/username.
   * This avoids "email already taken" collisions without needing MongoDB imports.
   */
  def uniqueTag(): String = System.nanoTime().toString.takeRight(8)

  "Database Baseline & Hydration Contract" should {

    "assign admin role only when registering the very first user, never otherwise" in new WithApplication {
      // This test runs against whatever database state the suite is pointed
      // at, which may already have users from a prior admin bootstrap or an
      // earlier spec in this run. So it does not hard-code "the first call
      // gets admin" (that was the previous, always-true assertion here) -
      // instead it reads the same precondition the controller itself uses
      // (MongodbDatasource.isAdmin(), i.e. "is the users collection empty
      // right now?") and asserts the registration matches that precondition.
      val db = app.injector.instanceOf[datasources.MongodbDatasource]
      val expectedType = if (db.isAdmin()) "admin" else "user"

      val tag = uniqueTag()
      val firstUserPayload = Json.obj(
        "name" -> s"Test Admin $tag",
        "email" -> s"admin_$tag@ejust.edu.eg",
        "username" -> s"test_admin_$tag",
        "password" -> "AdminPassword123!"
      )
      val regReq = route(app, FakeRequest(POST, "/api/user/register").withJsonBody(firstUserPayload)).get
      status(regReq) must equalTo(OK)
      val json = extractJson(regReq)
      (json \ "status").asOpt[String] must beSome("success")
      (json \ "newUser" \ "type").asOpt[String] must beSome(expectedType)
    }

    "assign user role to subsequent user registered after an admin exists" in new WithApplication {
      val tag = uniqueTag()
      // Seed an admin first (guaranteed unique)
      val seedPayload = Json.obj(
        "name" -> s"Seed Admin $tag",
        "email" -> s"seed_admin_$tag@ejust.edu.eg",
        "username" -> s"seed_admin_$tag",
        "password" -> "SeedPassword123!"
      )
      val seedReq = route(app, FakeRequest(POST, "/api/user/register").withJsonBody(seedPayload)).get
      status(seedReq) must equalTo(OK)  // await seed

      // Register second user with another unique identity
      val tag2 = (tag.toLong + 1).toString
      val userPayload = Json.obj(
        "name" -> s"Second User $tag2",
        "email" -> s"student_$tag2@ejust.edu.eg",
        "username" -> s"test_student_$tag2",
        "password" -> "StudentPassword123!"
      )
      val regReq = route(app, FakeRequest(POST, "/api/user/register").withJsonBody(userPayload)).get
      status(regReq) must equalTo(OK)
      val json = extractJson(regReq)
      (json \ "status").asOpt[String] must beSome("success")
      // Once an admin exists, all subsequent users must NOT receive admin role
      (json \ "newUser" \ "type").asOpt[String] must beSome("user")
    }

    "return valid empty space contract on fresh/empty database" in new WithApplication {
      val spacesReq = route(app, FakeRequest(POST, "/api/mapping/space/public").withJsonBody(Json.obj())).get
      status(spacesReq) must equalTo(OK)
      val json = extractJson(spacesReq)
      (json \ "spaces").asOpt[Seq[JsValue]] must beSome
      (json \ "buildings").asOpt[Seq[JsValue]] must beSome
    }

    // NOTE (R-14 / D-05): the above proves the role-assignment *logic* is
    // correct. It cannot prove a public attacker didn't win the race for
    // Administrator on a live empty deployment, because that depends on
    // network ingress timing, not application code. That guarantee comes
    // from running database/admin/bootstrap_admin.sh over loopback BEFORE
    // opening public ingress - see server/database/admin/README.md.
  }
}
