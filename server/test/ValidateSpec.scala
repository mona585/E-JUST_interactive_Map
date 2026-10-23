import org.specs2.mutable.Specification
import play.api.libs.json.Json
import utils.json.VALIDATE

/**
 * Closed-world validation: required keys need a type branch or String default; never 500.
 * Pure-function spec: no application, no database.
 */
class ValidateSpec extends Specification {

  "VALIDATE closed-world" should {

    "reject a numeric puid instead of crashing Poi construction" in {
      VALIDATE.checkRequirements(Json.obj("puid" -> 123, "buid" -> "b1"),
        "puid", "buid") must not beNull
    }

    "reject a numeric floor_number instead of crashing Floor/POI parsing" in {
      VALIDATE.checkRequirements(Json.obj("buid" -> "b1", "floor_number" -> 2),
        "buid", "floor_number") must not beNull
    }

    "reject non-numeric floorplan corner coordinates" in {
      VALIDATE.checkRequirements(Json.obj("bottom_left_lat" -> "north"),
        "bottom_left_lat") must not beNull
    }

    "accept numeric-string corner coordinates" in {
      VALIDATE.checkRequirements(Json.obj("bottom_left_lat" -> "31.12"),
        "bottom_left_lat") must beNull
    }

    "reject a non-numeric zoom" in {
      VALIDATE.checkRequirements(Json.obj("zoom" -> "far"), "zoom") must not beNull
    }

    "accept a numeric-string zoom" in {
      VALIDATE.checkRequirements(Json.obj("zoom" -> "20"), "zoom") must beNull
    }

    "still accept the campus buids string array (shape-checked downstream)" in {
      VALIDATE.checkRequirements(
        Json.obj("buids" -> Json.arr("buid_a", "buid_b")), "buids") must beNull
    }

    "report a missing key instead of passing" in {
      VALIDATE.checkRequirements(Json.obj("buid" -> "b1"), "buid", "puid") must not beNull
    }
  }

  "Space.changeOwner" should {

    "drop the new owner from co-owners without skipping entries" in {
      val space = new models.Space(Json.obj(
        "owner_id" -> "old_owner", "space_type" -> "building", "name" -> "H",
        "coordinates_lat" -> "30.9", "coordinates_lon" -> "29.7",
        "co_owners" -> Json.arr("new_owner", "keeper", "new_owner")))
      val out = Json.parse(space.changeOwner("new_owner"))
      (out \ "owner_id").asOpt[String] must beSome("new_owner")
      (out \ "co_owners").asOpt[Seq[String]] must beSome.which(_ == Seq("keeper"))
    }
  }

  "Google tokeninfo validation (fail-closed, no network)" should {

    val helper = new controllers.helper.User(null,
      play.api.Configuration("google.client.id" -> "test-client-id"))
    val good = Json.obj("aud" -> "test-client-id",
      "iss" -> "https://accounts.google.com", "expires_in" -> "3600",
      "sub" -> "google-123")

    "accept a fully valid token" in {
      helper.validateGoogleTokenInfo(good, Some("test-client-id")) must equalTo("google-123")
    }

    "reject audience mismatch" in {
      helper.validateGoogleTokenInfo(good, Some("other-client")) must beNull
    }

    "reject when google.client.id is unset (no open audience)" in {
      helper.validateGoogleTokenInfo(good, None) must beNull
    }

    "reject a missing audience" in {
      helper.validateGoogleTokenInfo(good - "aud", Some("test-client-id")) must beNull
    }

    "reject an untrusted issuer" in {
      helper.validateGoogleTokenInfo(
        good + ("iss" -> Json.toJson("https://evil.example.com")),
        Some("test-client-id")) must beNull
    }

    "reject an expired token" in {
      helper.validateGoogleTokenInfo(
        good + ("expires_in" -> Json.toJson("0")),
        Some("test-client-id")) must beNull
    }

    "reject a missing expiry (timeless tokens replay)" in {
      helper.validateGoogleTokenInfo(good - "expires_in", Some("test-client-id")) must beNull
    }

    "reject an absolute expiry in the past" in {
      helper.validateGoogleTokenInfo(
        good + ("exp" -> Json.toJson(1L)), Some("test-client-id")) must beNull
    }

    "accept a future absolute expiry when expires_in is absent" in {
      val future = System.currentTimeMillis() / 1000L + 3600L
      helper.validateGoogleTokenInfo(
        good - "expires_in" + ("exp" -> Json.toJson(future)),
        Some("test-client-id")) must equalTo("google-123")
    }

    "reject a subject-less token" in {
      helper.validateGoogleTokenInfo(good - "sub", Some("test-client-id")) must beNull
    }
  }
}
