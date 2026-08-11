import org.specs2.mutable.Specification
import play.api.test._
import play.api.test.Helpers._
import play.api.libs.json.{Json, JsValue}
import play.api.mvc.Result
import scala.concurrent.Future
import java.io.ByteArrayInputStream
import java.util.zip.GZIPInputStream

/**
 * Phase 9 Security and End-to-End Regression Gate
 *
 * Covers:
 * - Security headers present on API responses (via full filter pipeline)
 * - CORS: allowed origins echoed, disallowed origins NOT echoed
 * - Admin role protection: no later registrant can become Administrator
 * - Credential non-leakage in register responses
 * - Public API baseline contract
 */
class SecurityRegressionSpec extends PlaySpecification {

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

  def uniqueTag(): String = System.nanoTime().toString.takeRight(10)

  // Build an application that applies all configured filters (security headers, CORS, etc.)
  def filteredApp: play.api.Application = {
    import play.api.inject.guice.GuiceApplicationBuilder
    import play.filters.HttpFiltersComponents
    new GuiceApplicationBuilder()
      .configure("play.http.filters" -> "play.api.http.EnabledFilters")
      .build()
  }

  "Security Headers (via filter pipeline)" should {

    "include X-Frame-Options DENY on API response" in new WithApplication(filteredApp) {
      val req = route(app, FakeRequest(GET, "/api/version")).get
      status(req) must equalTo(OK)
      header("X-Frame-Options", req) must beSome("DENY")
    }

    "include X-Content-Type-Options nosniff on API response" in new WithApplication(filteredApp) {
      val req = route(app, FakeRequest(GET, "/api/version")).get
      status(req) must equalTo(OK)
      header("X-Content-Type-Options", req) must beSome("nosniff")
    }

    "include X-XSS-Protection on API response" in new WithApplication(filteredApp) {
      val req = route(app, FakeRequest(GET, "/api/version")).get
      status(req) must equalTo(OK)
      header("X-XSS-Protection", req) must beSome("1; mode=block")
    }

    "include Content-Security-Policy on API response" in new WithApplication(filteredApp) {
      val req = route(app, FakeRequest(GET, "/api/version")).get
      status(req) must equalTo(OK)
      header("Content-Security-Policy", req) must beSome
    }

  }

  "CORS Policy" should {

    "allow origin-less requests (same-origin API clients)" in new WithApplication {
      val req = route(app, FakeRequest(GET, "/api/version")).get
      status(req) must equalTo(OK)
    }

    "echo back Access-Control-Allow-Origin for allowed localhost origin" in new WithApplication {
      val req = route(app, FakeRequest(GET, "/api/version")
        .withHeaders("Origin" -> "http://localhost:9000")).get
      status(req) must equalTo(OK)
      header("Access-Control-Allow-Origin", req) must beSome("http://localhost:9000")
    }

    "not echo back disallowed external origin in CORS response" in new WithApplication {
      val req = route(app, FakeRequest(GET, "/api/version")
        .withHeaders("Origin" -> "https://evil.example.com")).get
      // CORS filter must NOT echo back the evil origin
      header("Access-Control-Allow-Origin", req) must beNone
    }

  }

  "Admin Role Protection" should {

    "not allow a third registrant to gain admin role" in new WithApplication {
      val tag = uniqueTag()
      // Register first user (will be admin if DB is empty, else user — both acceptable)
      val firstReq = route(app, FakeRequest(POST, "/api/user/register").withJsonBody(Json.obj(
        "name" -> s"First $tag",
        "email" -> s"first_$tag@ejust.edu.eg",
        "username" -> s"first_$tag",
        "password" -> "Password123!"
      ))).get
      status(firstReq) must equalTo(OK)

      // Register second user — at this point at least 1 user exists, so must be "user"
      val tag2 = (tag.toLong + 1).toString
      val secondReq = route(app, FakeRequest(POST, "/api/user/register").withJsonBody(Json.obj(
        "name" -> s"Second $tag2",
        "email" -> s"second_$tag2@ejust.edu.eg",
        "username" -> s"second_$tag2",
        "password" -> "Password123!"
      ))).get
      status(secondReq) must equalTo(OK)
      // The second user must always be "user", never "admin"
      (extractJson(secondReq) \ "newUser" \ "type").asOpt[String] must beSome("user")
    }

  }

  "Credential Security" should {

    "not include plaintext password in register response" in new WithApplication {
      val tag = uniqueTag()
      val payload = Json.obj(
        "name" -> s"Security Test $tag",
        "email" -> s"security_$tag@ejust.edu.eg",
        "username" -> s"security_$tag",
        "password" -> s"SecretPwd_$tag"
      )
      val regReq = route(app, FakeRequest(POST, "/api/user/register").withJsonBody(payload)).get
      status(regReq) must equalTo(OK)
      val body = extractString(regReq)
      // The actual password value must not appear in the response
      body must not contain s"SecretPwd_$tag"
    }

    "return error for missing required registration fields" in new WithApplication {
      val incompletePayload = Json.obj(
        "name" -> "Incomplete User"
        // missing email, username, password
      )
      val regReq = route(app, FakeRequest(POST, "/api/user/register").withJsonBody(incompletePayload)).get
      status(regReq) must equalTo(BAD_REQUEST)
    }

  }

  "Public API Baseline" should {

    "return version information without authentication" in new WithApplication {
      val req = route(app, FakeRequest(GET, "/api/version")).get
      status(req) must equalTo(OK)
      extractString(req) must contain("version")
    }

    "return spaces array on space/public endpoint" in new WithApplication {
      val req = route(app, FakeRequest(POST, "/api/mapping/space/public").withJsonBody(Json.obj())).get
      status(req) must equalTo(OK)
      (extractJson(req) \ "spaces").asOpt[Seq[JsValue]] must beSome
    }

    "require authentication for protected building creation endpoint" in new WithApplication {
      val payload = Json.obj(
        "name" -> "Test Building",
        "description" -> "Unauthorized creation attempt"
      )
      val req = route(app, FakeRequest(POST, "/api/mapping/space/add").withJsonBody(payload)).get
      // Should be unauthorized (401) or bad request without valid token
      status(req) must beOneOf(UNAUTHORIZED, BAD_REQUEST, FORBIDDEN)
    }

  }
}
