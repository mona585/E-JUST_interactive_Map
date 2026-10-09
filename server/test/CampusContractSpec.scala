import org.specs2.mutable.Specification
import play.api.test._
import play.api.test.Helpers._
import play.api.libs.json.{Json, JsValue}
import play.api.mvc.{AnyContentAsJson, Result}
import java.io.ByteArrayInputStream
import java.util.zip.GZIPInputStream
import scala.concurrent.Future

/**
 * Campus-only pilot contract (E-JUST outdoor, building-to-building).
 *
 * Covers the endpoints the pilot actually serves, on an empty-but-valid
 * database (init_schema.js). Indoor Wi-Fi stack (radiomap/heatmap/position)
 * is out of pilot scope and intentionally NOT asserted here; scope is
 * enforced at the Nginx edge, not by breaking API behavior field APKs use.
 */
class CampusContractSpec extends PlaySpecification {

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

  def db(implicit app: play.api.Application): datasources.ProxyDataSource =
    app.injector.instanceOf[datasources.ProxyDataSource]

  "Campus pilot liveness" should {

    "answer /api/health without authentication" in new WithApplication {
      val response = route(app, FakeRequest(GET, "/api/health")).get
      status(response) must equalTo(OK)
      (extractJson(response) \ "status").asOpt[String] must beSome("ok")
    }

    "answer /api/version without authentication" in new WithApplication {
      val response = route(app, FakeRequest(GET, "/api/version")).get
      status(response) must equalTo(OK)
      extractString(response) must contain("version")
    }
  }

  "Campus mapping baseline" should {

    "404 an unknown campus cuid instead of 500" in new WithApplication {
      val response = route(app, FakeRequest(POST, "/api/mapping/campus/get")
        .withJsonBody(Json.obj("cuid" -> "__none__"))).get
      status(response) must equalTo(NOT_FOUND)
    }

    "return an (empty-but-valid) spaces array on public endpoint" in new WithApplication {
      val response = route(app, FakeRequest(POST, "/api/mapping/space/public")
        .withJsonBody(Json.obj())).get
      status(response) must equalTo(OK)
      val json = extractJson(response)
      (json \ "spaces").asOpt[Seq[JsValue]] must beSome
    }
  }

  "Navigation guards (campus pilot)" should {    "reject a route between unknown POIs with 400, not 500" in new WithApplication {
      val response = route(app, FakeRequest(POST, "/api/navigation/route")
        .withJsonBody(Json.obj("pois_from" -> "puid_does_not_exist_a",
          "pois_to" -> "puid_does_not_exist_b"))).get
      status(response) must equalTo(BAD_REQUEST)
    }

    "reject same source and destination with 400" in new WithApplication {
      val response = route(app, FakeRequest(POST, "/api/navigation/route")
        .withJsonBody(Json.obj("pois_from" -> "puid_same",
          "pois_to" -> "puid_same"))).get
      status(response) must equalTo(BAD_REQUEST)
      extractString(response) must contain("same")
    }
  }

  "Campus outdoor routing" should {

    "plot a path between two buildings over outdoor edges" in new WithApplication {
      val tag = System.nanoTime().toString.takeRight(8)
      val cuid = s"cuid_contract_$tag"
      val buidA = s"buid_contract_a_$tag"
      val buidB = s"buid_contract_b_$tag"
      val puidA = s"puid_contract_a_$tag"
      val puidB = s"puid_contract_b_$tag"
      val db = app.injector.instanceOf[datasources.ProxyDataSource]
      db.addJson("campuses", Json.obj("cuid" -> cuid, "name" -> "Contract",
        "description" -> "t", "greeklish" -> "false",
        "buids" -> Json.arr(buidA, buidB), "owner_id" -> "test"))
      db.addJson("pois", Json.obj("puid" -> puidA, "buid" -> buidA,
        "floor_number" -> "0", "name" -> "Gate A",
        "coordinates_lat" -> "30.9501", "coordinates_lon" -> "29.7501",
        "pois_type" -> "Entrance"))
      db.addJson("pois", Json.obj("puid" -> puidB, "buid" -> buidB,
        "floor_number" -> "0", "name" -> "Gate B",
        "coordinates_lat" -> "30.9510", "coordinates_lon" -> "29.7510",
        "pois_type" -> "Entrance"))
      db.addJson("edges", Json.obj("cuid" -> s"conn_${puidA}_${puidB}",
        "pois_a" -> puidA, "pois_b" -> puidB,
        "buid_a" -> buidA, "buid_b" -> buidB,
        "floor_a" -> "0", "floor_b" -> "0", "buid" -> buidA,
        "edge_type" -> "outdoor", "weight" -> "180.0",
        "is_published" -> "true"))
      try {
        val response = route(app, FakeRequest(POST, "/api/navigation/route/campus")
          .withJsonBody(Json.obj("cuid" -> cuid,
            "pois_from" -> puidA, "pois_to" -> puidB))).get
        status(response) must equalTo(OK)
        val json = extractJson(response)
        (json \ "num_of_pois").asOpt[Int] must beSome(2)
        (json \ "pois" \ 0 \ "puid").asOpt[String] must beSome(puidA)
        (json \ "pois" \ 1 \ "puid").asOpt[String] must beSome(puidB)
        (json \ "pois" \ 1 \ "buid").asOpt[String] must beSome(buidB)
      } finally {
        db.deleteFromKey("edges", "cuid", s"conn_${puidA}_${puidB}")
        db.deleteFromKey("pois", "puid", puidA)
        db.deleteFromKey("pois", "puid", puidB)
        db.deleteFromKey("campuses", "cuid", cuid)
      }
    }

    "400 when a POI sits outside the campus" in new WithApplication {
      val tag = System.nanoTime().toString.takeRight(8)
      val cuid = s"cuid_contract_out_$tag"
      val buidA = s"buid_contract_out_a_$tag"
      val puidA = s"puid_contract_out_a_$tag"
      val db = app.injector.instanceOf[datasources.ProxyDataSource]
      db.addJson("campuses", Json.obj("cuid" -> cuid, "name" -> "Contract",
        "description" -> "t", "greeklish" -> "false",
        "buids" -> Json.arr(buidA), "owner_id" -> "test"))
      db.addJson("pois", Json.obj("puid" -> puidA, "buid" -> buidA,
        "floor_number" -> "0", "name" -> "Gate A",
        "coordinates_lat" -> "30.9501", "coordinates_lon" -> "29.7501",
        "pois_type" -> "Entrance"))
      try {
        val response = route(app, FakeRequest(POST, "/api/navigation/route/campus")
          .withJsonBody(Json.obj("cuid" -> cuid,
            "pois_from" -> puidA, "pois_to" -> "puid_does_not_exist"))).get
        status(response) must equalTo(BAD_REQUEST)
      } finally {
        db.deleteFromKey("pois", "puid", puidA)
        db.deleteFromKey("campuses", "cuid", cuid)
      }
    }

    "400 unknown POIs before campus resolution" in new WithApplication {
      val response = route(app, FakeRequest(POST, "/api/navigation/route/campus")
        .withJsonBody(Json.obj("cuid" -> "cuid_does_not_exist",
          "pois_from" -> "puid_does_not_exist_a",
          "pois_to" -> "puid_does_not_exist_b"))).get
      // POI resolution precedes campus resolution: deterministic 400.
      status(response) must equalTo(BAD_REQUEST)
    }
  }

  "Auth hardening" should {

    "register PBKDF2 hashes and log in, rejecting wrong passwords" in new WithApplication {
      val tag = System.nanoTime().toString.takeRight(8)
      val username = s"contract_auth_$tag"
      val reg = route(app, FakeRequest(POST, "/api/user/register").withJsonBody(Json.obj(
        "name" -> s"Contract $tag",
        "email" -> s"contract_$tag@ejust.edu.eg",
        "username" -> username,
        "password" -> "Password123!"))).get
      status(reg) must equalTo(OK)
      try {
        val stored = db.getFromKeyAsJson("users", "username", username)
        stored must not beNull;
        (stored \ "password").asOpt[String] must beSome.which(_.startsWith("pbkdf2$"))
        val ok = route(app, FakeRequest(POST, "/api/user/login").withJsonBody(Json.obj(
          "username" -> username, "password" -> "Password123!"))).get
        status(ok) must equalTo(OK)
        (extractJson(ok) \ "user" \ "password").asOpt[String] must beNone
        val bad = route(app, FakeRequest(POST, "/api/user/login").withJsonBody(Json.obj(
          "username" -> username, "password" -> "WrongPass1!"))).get
        status(bad) must equalTo(BAD_REQUEST)
      } finally {
        db.deleteFromKey("users", "username", username)
      }
    }

    "still verify legacy SHA-256 rows (bug-compatible hex)" in new WithApplication {
      val tag = System.nanoTime().toString.takeRight(8)
      val username = s"contract_legacy_$tag"
      // Replicates helper.User legacy derivation incl. its nibble-drop quirk,
      // because production rows were written by that exact routine.
      def legacyHex(password: String): String = {
        val md = java.security.MessageDigest.getInstance("SHA-256")
        val sb = new StringBuffer
        md.digest(("test-salt" + password + "test-pepper").getBytes("UTF-8")) foreach { b =>
          val hex = Integer.toHexString(0xFF & b)
          if (hex.length == 1) sb.append('0') else sb.append(hex)
        }
        sb.toString
      }
      db.addJson("users", Json.obj("name" -> "Legacy", "email" -> s"legacy_$tag@ejust.edu.eg",
        "username" -> username, "password" -> legacyHex("LegacyPass1!"),
        "access_token" -> s"apLocal_contract_$tag", "external" -> "anyplace",
        "type" -> "user", "owner_id" -> s"${username}_local"))
      try {
        val ok = route(app, FakeRequest(POST, "/api/user/login").withJsonBody(Json.obj(
          "username" -> username, "password" -> "LegacyPass1!"))).get
        status(ok) must equalTo(OK)
        val bad = route(app, FakeRequest(POST, "/api/user/login").withJsonBody(Json.obj(
          "username" -> username, "password" -> "Nope12345!"))).get
        status(bad) must equalTo(BAD_REQUEST)
      } finally {
        db.deleteFromKey("users", "username", username)
      }
    }

    "401 floorplan upload without a token" in new WithApplication {
      val response = route(app, FakeRequest(POST, "/api/mapping/floor/floorplan/upload")
        .withJsonBody(Json.obj("buid" -> "x", "floor_number" -> "0"))).get
      status(response) must equalTo(UNAUTHORIZED)
    }

    "401 radiomap delete/time without a token" in new WithApplication {
      val response = route(app, FakeRequest(POST, "/api/auth/radiomap/delete/time")
        .withJsonBody(Json.obj("buid" -> "x", "floor" -> "0",
          "lat1" -> "0", "lon1" -> "0", "lat2" -> "1", "lon2" -> "1",
          "timestampX" -> "0", "timestampY" -> "1"))).get
      status(response) must equalTo(UNAUTHORIZED)
    }

    "report version and uptime on /api/health" in new WithApplication {
      val response = route(app, FakeRequest(GET, "/api/health")).get
      status(response) must equalTo(OK)
      val json = extractJson(response)
      (json \ "version").asOpt[String] must beSome
      (json \ "uptime_ms").asOpt[Long] must beSome
    }

    "forbid moderators changing other users' passwords" in new WithApplication {
      val tag = System.nanoTime().toString.takeRight(8)
      val modToken = s"apLocal_contract_mod_$tag"
      val modOwner = s"contract_mod_${tag}_local"
      val victimOwner = s"contract_victim_${tag}_local"
      db.addJson("users", Json.obj("name" -> "Mod", "email" -> s"mod_$tag@ejust.edu.eg",
        "username" -> s"contract_mod_$tag", "password" -> "x",
        "access_token" -> modToken, "external" -> "anyplace",
        "type" -> "moderator", "owner_id" -> modOwner))
      db.addJson("users", Json.obj("name" -> "Victim", "email" -> s"victim_$tag@ejust.edu.eg",
        "username" -> s"contract_victim_$tag", "password" -> "x",
        "access_token" -> s"apLocal_contract_victim_$tag", "external" -> "anyplace",
        "type" -> "user", "owner_id" -> victimOwner))
      try {
        // Moderator/admin lists are boot-cached statics: refresh so the
        // fixture moderator is recognized (mirrors login/refresh behavior).
        datasources.MongodbDatasource.updateCachedModerators()
        def authed(body: JsValue) = FakeRequest(POST, "/api/auth/user/update",
          FakeHeaders(Seq("access_token" -> modToken, "Content-Type" -> "application/json")),
          AnyContentAsJson(body))
        val denied = route(app, authed(Json.obj("user_id" -> victimOwner, "password" -> "Taken123!"))).get
        status(denied) must equalTo(FORBIDDEN)
        val selfOk = route(app, authed(Json.obj("user_id" -> modOwner, "password" -> "Self12345!"))).get
        status(selfOk) must equalTo(OK)
      } finally {
        db.deleteFromKey("users", "username", s"contract_mod_$tag")
        db.deleteFromKey("users", "username", s"contract_victim_$tag")
      }
    }

    "reject traversal identifiers on tile endpoints" in new WithApplication {
      val evil = route(app, FakeRequest(POST, "/api/floortiles/zip/../..//0")
        .withJsonBody(Json.obj())).get
      status(evil) must beOneOf(NOT_FOUND, BAD_REQUEST)
      val evilTiles = route(app, FakeRequest(GET, "/api/floortiles/buid_eng/0/..%2F..%2Fetc%2Fhostname")).get
      status(evilTiles) must beOneOf(NOT_FOUND, BAD_REQUEST)
    }
  }

  "Campus outdoor routing edges" should {

    "400 same POI twice on /route/campus" in new WithApplication {
      val response = route(app, FakeRequest(POST, "/api/navigation/route/campus")
        .withJsonBody(Json.obj("cuid" -> "c", "pois_from" -> "p", "pois_to" -> "p"))).get
      status(response) must equalTo(BAD_REQUEST)
    }

    "400 a missing cuid on /route/campus" in new WithApplication {
      val response = route(app, FakeRequest(POST, "/api/navigation/route/campus")
        .withJsonBody(Json.obj("pois_from" -> "p", "pois_to" -> "q"))).get
      status(response) must equalTo(BAD_REQUEST)
    }

    "404 unknown campus with known POIs" in new WithApplication {
      val tag = System.nanoTime().toString.takeRight(8)
      val buid = s"buid_contract_nc_$tag"
      val puidA = s"puid_contract_nc_a_$tag"
      val puidB = s"puid_contract_nc_b_$tag"
      for (puid <- Seq(puidA, puidB)) {
        db.addJson("pois", Json.obj("puid" -> puid, "buid" -> buid,
          "floor_number" -> "0", "name" -> "Gate",
          "coordinates_lat" -> "30.9501", "coordinates_lon" -> "29.7501",
          "pois_type" -> "Entrance"))
      }
      try {
        val response = route(app, FakeRequest(POST, "/api/navigation/route/campus")
          .withJsonBody(Json.obj("cuid" -> s"cuid_missing_$tag",
            "pois_from" -> puidA, "pois_to" -> puidB))).get
        status(response) must equalTo(NOT_FOUND)
      } finally {
        db.deleteFromKey("pois", "puid", puidA)
        db.deleteFromKey("pois", "puid", puidB)
      }
    }

    "400 disconnected campus POIs with a clear message" in new WithApplication {
      val tag = System.nanoTime().toString.takeRight(8)
      val cuid = s"cuid_contract_dc_$tag"
      val buidA = s"buid_contract_dc_a_$tag"
      val buidB = s"buid_contract_dc_b_$tag"
      val puidA = s"puid_contract_dc_a_$tag"
      val puidB = s"puid_contract_dc_b_$tag"
      db.addJson("campuses", Json.obj("cuid" -> cuid, "name" -> "DC",
        "description" -> "t", "greeklish" -> "false",
        "buids" -> Json.arr(buidA, buidB), "owner_id" -> "test"))
      db.addJson("pois", Json.obj("puid" -> puidA, "buid" -> buidA,
        "floor_number" -> "0", "name" -> "A",
        "coordinates_lat" -> "30.9501", "coordinates_lon" -> "29.7501",
        "pois_type" -> "Entrance"))
      db.addJson("pois", Json.obj("puid" -> puidB, "buid" -> buidB,
        "floor_number" -> "0", "name" -> "B",
        "coordinates_lat" -> "30.9510", "coordinates_lon" -> "29.7510",
        "pois_type" -> "Entrance"))
      try {
        val response = route(app, FakeRequest(POST, "/api/navigation/route/campus")
          .withJsonBody(Json.obj("cuid" -> cuid,
            "pois_from" -> puidA, "pois_to" -> puidB))).get
        status(response) must equalTo(BAD_REQUEST)
        extractString(response) must contain("No outdoor path")
      } finally {
        db.deleteFromKey("pois", "puid", puidA)
        db.deleteFromKey("pois", "puid", puidB)
        db.deleteFromKey("campuses", "cuid", cuid)
      }
    }
  }
}
