import datasources.SCHEMA
import models.oauth.OAuth2Request
import org.specs2.mutable.Specification
import play.api.libs.json.{JsNull, Json}
import play.api.test.FakeRequest

class OAuth2RequestSpec extends Specification {

  "OAuth2Request body parsing" should {

    "read unquoted string parameters from JSON bodies" in {
      val req = new OAuth2Request(FakeRequest().withJsonBody(
        Json.obj("name" -> "Ada", "count" -> 3, "nil" -> JsNull)))
      req.hasJsonBody() must beTrue
      req.hasFormEncodedBody() must beFalse
      req.getParameter("name") must equalTo("Ada")
      req.getParameter("count") must equalTo("3")
      req.getParameter("nil") must beNull
      req.getParameter("missing") must beNull
    }

    "read parameters from form-url-encoded bodies" in {
      val req = new OAuth2Request(FakeRequest().withFormUrlEncodedBody(
        "name" -> "Ada", "empty" -> ""))
      req.hasJsonBody() must beFalse
      req.hasFormEncodedBody() must beTrue
      req.getParameter("name") must equalTo("Ada")
      req.getParameter("empty") must equalTo("")
      req.getParameter("missing") must beNull
    }

    "reject empty parameter names" in {
      val req = new OAuth2Request(FakeRequest().withJsonBody(Json.obj("name" -> "Ada")))
      req.getParameter("") must throwA[IllegalArgumentException]
    }

    "return null for a missing access token" in {
      val req = new OAuth2Request(FakeRequest())
      req.getAccessToken() must beNull
    }

    "read the access token from headers" in {
      val req = new OAuth2Request(
        FakeRequest().withHeaders(SCHEMA.fAccessToken -> "token-value"))
      req.getAccessToken() must equalTo("token-value")
    }
  }
}
