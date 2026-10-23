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
 * Empty-but-valid DB; indoor Wi-Fi stack out of scope (enforced at Nginx edge).
 */
class CampusContractSpec extends PlaySpecification with IsolatedFixture {

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

  if (!MongoTestSupport.enabled) {
    "Mongo-backed campus contract" should {
      "run only against the controlled test database" in skipped(MongoTestSupport.skipMessage)
    }
  } else {

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
      contentType(response) must beSome("application/json")
      val json = extractJson(response)
      (json \ "spaces").asOpt[Seq[JsValue]] must beSome
    }

    "return campus spaces in buids order and skip deleted buildings" in new WithApplication {
      val tag = freshTag()
      val cuid = s"cuid_order_$tag"
      val first = s"buid_order_first_$tag"
      val second = s"buid_order_second_$tag"
      val missing = s"buid_order_missing_$tag"
      seed("campuses", Json.obj("cuid" -> cuid, "name" -> "Order Campus",
        "buids" -> Json.arr(second, first, missing)))
      seed("spaces", Json.obj("buid" -> first, "name" -> "First", "is_published" -> "true"))
      seed("spaces", Json.obj("buid" -> second, "name" -> "Second", "is_published" -> "true"))
      try {
        val response = route(app, FakeRequest(POST, "/api/mapping/campus/get")
          .withJsonBody(Json.obj("cuid" -> cuid))).get
        status(response) must equalTo(OK)
        val spaces = (extractJson(response) \ "spaces").as[Seq[JsValue]]
        spaces.flatMap(space => (space \ "buid").asOpt[String]) must equalTo(Seq(second, first))
      } finally {
        db.deleteFromKey("spaces", "buid", first)
        db.deleteFromKey("spaces", "buid", second)
        db.deleteFromKey("campuses", "cuid", cuid)
      }
    }
  }

  "Campus POI search" should {

    "return each greeklish match once across multi-word queries" in new WithApplication {
      val tag = freshTag()
      val cuid = s"cuid_search_$tag"
      val buid = s"buid_search_$tag"
      val matchPuid = s"puid_search_match_$tag"
      val otherPuid = s"puid_search_other_$tag"
      seed("campuses", Json.obj("cuid" -> cuid, "name" -> "Search Campus",
        "description" -> "t", "greeklish" -> "false", "buids" -> Json.arr(buid)))
      seed("pois", Json.obj("puid" -> matchPuid, "buid" -> buid, "floor_number" -> "0",
        "name" -> "Καφετερια", "description" -> "Coffee place",
        "coordinates_lat" -> "35.0", "coordinates_lon" -> "33.0", "pois_type" -> "Room"))
      seed("pois", Json.obj("puid" -> otherPuid, "buid" -> buid, "floor_number" -> "0",
        "name" -> "Library", "description" -> "Quiet study",
        "coordinates_lat" -> "35.1", "coordinates_lon" -> "33.1", "pois_type" -> "Room"))
      try {
        val byCampus = route(app, FakeRequest(POST, "/api/mapping/pois/search")
          .withJsonBody(Json.obj("cuid" -> cuid, "letters" -> "kafeteria coffee",
            "greeklish" -> "true"))).get
        status(byCampus) must equalTo(OK)
        val campusPois = (extractJson(byCampus) \ "pois").asOpt[Seq[JsValue]].get
        campusPois.count(p => (p \ "puid").asOpt[String].contains(matchPuid)) must equalTo(1)
        campusPois.exists(p => (p \ "puid").asOpt[String].contains(otherPuid)) must beFalse

        val byBuilding = route(app, FakeRequest(POST, "/api/mapping/pois/search")
          .withJsonBody(Json.obj("buid" -> buid, "letters" -> "kafeteria coffee"))).get
        status(byBuilding) must equalTo(OK)
        val buildingPois = (extractJson(byBuilding) \ "pois").asOpt[Seq[JsValue]].get
        buildingPois.count(p => (p \ "puid").asOpt[String].contains(matchPuid)) must equalTo(1)
      } finally {
        db.deleteFromKey("pois", "puid", matchPuid)
        db.deleteFromKey("pois", "puid", otherPuid)
        db.deleteFromKey("campuses", "cuid", cuid)
      }
    }
  }

  "Navigation guards (campus pilot)" should {    "404 a route between unknown POIs, not 500" in new WithApplication {
      val response = route(app, FakeRequest(POST, "/api/navigation/route")
        .withJsonBody(Json.obj("pois_from" -> "puid_does_not_exist_a",
          "pois_to" -> "puid_does_not_exist_b"))).get
      status(response) must equalTo(NOT_FOUND)
    }

    "reject same source and destination with 400" in new WithApplication {
      val response = route(app, FakeRequest(POST, "/api/navigation/route")
        .withJsonBody(Json.obj("pois_from" -> "puid_same",
          "pois_to" -> "puid_same"))).get
      status(response) must equalTo(BAD_REQUEST)
      extractString(response) must contain("same")
    }

    "400 (not 500) a POI byFloor call with a numeric floor_number" in new WithApplication {
      val response = route(app, FakeRequest(POST, "/api/mapping/pois/floor/all")
        .withJsonBody(Json.obj("buid" -> "buid_does_not_exist", "floor_number" -> 2))).get
      status(response) must equalTo(BAD_REQUEST)
    }

    "400 (not 500) a POI bySpace call with a numeric buid" in new WithApplication {
      val response = route(app, FakeRequest(POST, "/api/mapping/pois/space/all")
        .withJsonBody(Json.obj("buid" -> 123))).get
      status(response) must equalTo(BAD_REQUEST)
    }
  }

  "S1 data integrity" should {

    def authed(app: play.api.Application, path: String, token: String, body: JsValue) =
      route(app, FakeRequest(POST, path,
        FakeHeaders(Seq("access_token" -> token, "Content-Type" -> "application/json")),
        AnyContentAsJson(body))).get

    "mint and persist a cuid when campus add omits it" in new WithApplication {
      val tag = freshTag()
      val token = s"apLocal_s1_$tag"
      val owner = s"s1_${tag}_local"
      val buid = s"buid_s1_$tag"
      seed("users", Json.obj("name" -> "S1", "email" -> s"s1_$tag@ejust.edu.eg",
        "username" -> s"s1_$tag", "password" -> "x",
        "access_token" -> token, "external" -> "anyplace",
        "type" -> "user", "owner_id" -> owner))
      seed("spaces", Json.obj("buid" -> buid, "name" -> "S1 Hall",
        "description" -> "t", "owner_id" -> owner, "is_published" -> "true"))
      try {
        val add = authed(app, "/api/auth/mapping/campus/add", token, Json.obj(
          "name" -> "S1 Campus", "description" -> "t",
          "buids" -> Json.arr(buid), "greeklish" -> "false"))
        status(add) must equalTo(OK)
        val cuid = (extractJson(add) \ "cuid").asOpt[String]
        cuid must beSome.which(_.trim.nonEmpty)
        // The minted cuid must resolve: no orphaned row.
        val get = route(app, FakeRequest(POST, "/api/mapping/campus/get")
          .withJsonBody(Json.obj("cuid" -> cuid.get))).get
        status(get) must equalTo(OK)
        db.deleteFromKey("campuses", "cuid", cuid.get)
      } finally {
        db.deleteFromKey("spaces", "buid", buid)
        db.deleteFromKey("users", "username", s"s1_$tag")
      }
    }

    "403 campus add grafting a foreign building" in new WithApplication {
      val tag = freshTag()
      val token = s"apLocal_s1f_$tag"
      val owner = s"s1f_${tag}_local"
      seed("users", Json.obj("name" -> "S1", "email" -> s"s1f_$tag@ejust.edu.eg",
        "username" -> s"s1f_$tag", "password" -> "x",
        "access_token" -> token, "external" -> "anyplace",
        "type" -> "user", "owner_id" -> owner))
      seed("spaces", Json.obj("buid" -> s"buid_s1v_$tag", "name" -> "Victim",
        "description" -> "t", "owner_id" -> "someone_else", "is_published" -> "true"))
      try {
        val add = authed(app, "/api/auth/mapping/campus/add", token, Json.obj(
          "name" -> "Hijack", "description" -> "t",
          "buids" -> Json.arr(s"buid_s1v_$tag"), "greeklish" -> "false"))
        status(add) must equalTo(FORBIDDEN)
      } finally {
        db.deleteFromKey("spaces", "buid", s"buid_s1v_$tag")
        db.deleteFromKey("users", "username", s"s1f_$tag")
      }
    }

    "404 POI add on a nonexistent floor (no orphans)" in new WithApplication {
      val tag = freshTag()
      val token = s"apLocal_s1p_$tag"
      val owner = s"s1p_${tag}_local"
      val buid = s"buid_s1p_$tag"
      seed("users", Json.obj("name" -> "S1", "email" -> s"s1p_$tag@ejust.edu.eg",
        "username" -> s"s1p_$tag", "password" -> "x",
        "access_token" -> token, "external" -> "anyplace",
        "type" -> "user", "owner_id" -> owner))
      seed("spaces", Json.obj("buid" -> buid, "name" -> "S1 Hall",
        "description" -> "t", "owner_id" -> owner, "is_published" -> "true"))
      try {
        val add = authed(app, "/api/auth/mapping/pois/add", token, Json.obj(
          "is_published" -> "true", "buid" -> buid, "floor_name" -> "Ground",
          "floor_number" -> "99", "name" -> "Ghost", "pois_type" -> "Room",
          "is_door" -> "false", "is_building_entrance" -> "false",
          "coordinates_lat" -> "30.9", "coordinates_lon" -> "29.7"))
        status(add) must equalTo(NOT_FOUND)
      } finally {
        db.deleteFromKey("spaces", "buid", buid)
        db.deleteFromKey("users", "username", s"s1p_$tag")
      }
    }

    "400 duplicate floor add" in new WithApplication {
      val tag = freshTag()
      val token = s"apLocal_s1d_$tag"
      val owner = s"s1d_${tag}_local"
      val buid = s"buid_s1d_$tag"
      seed("users", Json.obj("name" -> "S1", "email" -> s"s1d_$tag@ejust.edu.eg",
        "username" -> s"s1d_$tag", "password" -> "x",
        "access_token" -> token, "external" -> "anyplace",
        "type" -> "user", "owner_id" -> owner))
      seed("spaces", Json.obj("buid" -> buid, "name" -> "S1 Hall",
        "description" -> "t", "owner_id" -> owner, "is_published" -> "true"))
      val floor = Json.obj("is_published" -> "true", "buid" -> buid,
        "floor_name" -> "Ground", "description" -> "t", "floor_number" -> "0")
      try {
        status(authed(app, "/api/auth/mapping/floor/add", token, floor)) must equalTo(OK)
        status(authed(app, "/api/auth/mapping/floor/add", token, floor)) must equalTo(BAD_REQUEST)
      } finally {
        db.deleteFromKey("floorplans", "fuid", s"${buid}_0")
        db.deleteFromKey("spaces", "buid", buid)
        db.deleteFromKey("users", "username", s"s1d_$tag")
      }
    }

    "400 radiomap file fetch without a body, not 500" in new WithApplication {
      val response = route(app, FakeRequest(POST, "/api/radiomaps/folder/file")).get
      status(response) must equalTo(BAD_REQUEST)
    }
  }

  "S2 auth hardening" should {

    def authedS2(app: play.api.Application, path: String, token: String, body: JsValue) =
      route(app, FakeRequest(POST, path,
        FakeHeaders(Seq("access_token" -> token, "Content-Type" -> "application/json")),
        AnyContentAsJson(body))).get

    "403 when a moderator edits an admin, 200 on a regular user" in new WithApplication {
      val tag = freshTag()
      val modToken = s"apLocal_s2m_$tag"
      val modOwner = s"s2m_${tag}_local"
      val adminOwner = s"s2a_${tag}_local"
      seed("users", Json.obj("name" -> "Mod", "email" -> s"s2m_$tag@ejust.edu.eg",
        "username" -> s"s2m_$tag", "password" -> "x", "access_token" -> modToken,
        "external" -> "anyplace", "type" -> "moderator", "owner_id" -> modOwner))
      seed("users", Json.obj("name" -> "Admin", "email" -> s"s2a_$tag@ejust.edu.eg",
        "username" -> s"s2a_$tag", "password" -> "x", "access_token" -> s"apLocal_s2a_$tag",
        "external" -> "anyplace", "type" -> "admin", "owner_id" -> adminOwner))
      seed("users", Json.obj("name" -> "Regular", "email" -> s"s2r_$tag@ejust.edu.eg",
        "username" -> s"s2r_$tag", "password" -> "x", "access_token" -> s"apLocal_s2r_$tag",
        "external" -> "anyplace", "type" -> "user", "owner_id" -> s"s2r_${tag}_local"))
      datasources.MongodbDatasource.updateCachedModerators()
      try {
        val denied = authedS2(app, "/api/auth/user/update", modToken, Json.obj(
          "user_id" -> adminOwner, "name" -> "Pwned"))
        status(denied) must equalTo(FORBIDDEN)
        val allowed = authedS2(app, "/api/auth/user/update", modToken, Json.obj(
          "user_id" -> s"s2r_${tag}_local", "name" -> "Fixed Name"))
        status(allowed) must equalTo(OK)
      } finally {
        db.deleteFromKey("users", "username", s"s2m_$tag")
        db.deleteFromKey("users", "username", s"s2a_$tag")
        db.deleteFromKey("users", "username", s"s2r_$tag")
        datasources.MongodbDatasource.updateCachedModerators()
      }
    }

    "stamp token expiry at registration" in new WithApplication {
      val tag = freshTag()
      val username = s"s2exp_$tag"
      val reg = route(app, FakeRequest(POST, "/api/user/register").withJsonBody(Json.obj(
        "name" -> s"S2 $tag", "email" -> s"s2exp_$tag@ejust.edu.eg",
        "username" -> username, "password" -> "Password123!"))).get
      status(reg) must equalTo(OK)
      try {
        val exp = (db.getFromKeyAsJson("users", "username", username) \ "token_expires")
          .asOpt[String].map(_.toLong)
        exp must beSome.which(_ > System.currentTimeMillis())
      } finally {
        db.deleteFromKey("users", "username", username)
      }
    }

    "rotate a legacy unstamped token on login" in new WithApplication {
      val tag = freshTag()
      val username = s"s2leg_$tag"
      val oldToken = s"apLocal_s2leg_$tag"
      val md = java.security.MessageDigest.getInstance("SHA-256")
      val sb = new StringBuffer
      md.digest(("test-salt" + "LegacyPass1!" + "test-pepper").getBytes("UTF-8")) foreach { b =>
        val hex = Integer.toHexString(0xFF & b)
        if (hex.length == 1) sb.append('0') else sb.append(hex)
      }
      // Legacy row: valid token, no expiry stamp.
      seed("users", Json.obj("name" -> "Legacy", "email" -> s"s2leg_$tag@ejust.edu.eg",
        "username" -> username, "password" -> sb.toString,
        "access_token" -> oldToken, "external" -> "anyplace",
        "type" -> "user", "owner_id" -> s"${username}_local"))
      try {
        val login = route(app, FakeRequest(POST, "/api/user/login").withJsonBody(Json.obj(
          "username" -> username, "password" -> "LegacyPass1!"))).get
        status(login) must equalTo(OK)
        val newToken = (extractJson(login) \ "user" \ "access_token").as[String]
        newToken must not equalTo oldToken
        val exp = (db.getFromKeyAsJson("users", "username", username) \ "token_expires")
          .asOpt[String].map(_.toLong)
        exp must beSome.which(_ > System.currentTimeMillis())
      } finally {
        db.deleteFromKey("users", "username", username)
      }
    }

    "400 an over-long password at registration" in new WithApplication {
      val tag = freshTag()
      val long = "Aa1!" + "x" * 125
      long.length must be_>(128)
      val reg = route(app, FakeRequest(POST, "/api/user/register").withJsonBody(Json.obj(
        "name" -> s"S2 $tag", "email" -> s"s2long_$tag@ejust.edu.eg",
        "username" -> s"s2long_$tag", "password" -> long))).get
      status(reg) must equalTo(BAD_REQUEST)
      db.deleteFromKey("users", "username", s"s2long_$tag")
    }
  }

  "Campus outdoor routing" should {

    "plot a path between two buildings over outdoor edges" in new WithApplication {
      val tag = freshTag()
      val cuid = s"cuid_contract_$tag"
      val buidA = s"buid_contract_a_$tag"
      val buidB = s"buid_contract_b_$tag"
      val puidA = s"puid_contract_a_$tag"
      val puidB = s"puid_contract_b_$tag"
      val db = app.injector.instanceOf[datasources.ProxyDataSource]
      seed("campuses", Json.obj("cuid" -> cuid, "name" -> "Contract",
        "description" -> "t", "greeklish" -> "false",
        "buids" -> Json.arr(buidA, buidB), "owner_id" -> "test"))
      seed("pois", Json.obj("puid" -> puidA, "buid" -> buidA,
        "floor_number" -> "0", "name" -> "Gate A",
        "coordinates_lat" -> "30.9501", "coordinates_lon" -> "29.7501",
        "pois_type" -> "Entrance"))
      seed("pois", Json.obj("puid" -> puidB, "buid" -> buidB,
        "floor_number" -> "0", "name" -> "Gate B",
        "coordinates_lat" -> "30.9510", "coordinates_lon" -> "29.7510",
        "pois_type" -> "Entrance"))
      seed("edges", Json.obj("cuid" -> s"conn_${puidA}_${puidB}",
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

    "404 when a campus POI routes to an unknown POI" in new WithApplication {
      val tag = freshTag()
      val cuid = s"cuid_contract_out_$tag"
      val buidA = s"buid_contract_out_a_$tag"
      val puidA = s"puid_contract_out_a_$tag"
      val db = app.injector.instanceOf[datasources.ProxyDataSource]
      seed("campuses", Json.obj("cuid" -> cuid, "name" -> "Contract",
        "description" -> "t", "greeklish" -> "false",
        "buids" -> Json.arr(buidA), "owner_id" -> "test"))
      seed("pois", Json.obj("puid" -> puidA, "buid" -> buidA,
        "floor_number" -> "0", "name" -> "Gate A",
        "coordinates_lat" -> "30.9501", "coordinates_lon" -> "29.7501",
        "pois_type" -> "Entrance"))
      try {
        val response = route(app, FakeRequest(POST, "/api/navigation/route/campus")
          .withJsonBody(Json.obj("cuid" -> cuid,
            "pois_from" -> puidA, "pois_to" -> "puid_does_not_exist"))).get
        status(response) must equalTo(NOT_FOUND)
      } finally {
        db.deleteFromKey("pois", "puid", puidA)
        db.deleteFromKey("campuses", "cuid", cuid)
      }
    }

    "404 unknown POIs before campus resolution" in new WithApplication {
      val response = route(app, FakeRequest(POST, "/api/navigation/route/campus")
        .withJsonBody(Json.obj("cuid" -> "cuid_does_not_exist",
          "pois_from" -> "puid_does_not_exist_a",
          "pois_to" -> "puid_does_not_exist_b"))).get
      // POI resolution precedes campus resolution: deterministic 404.
      status(response) must equalTo(NOT_FOUND)
    }
  }

  "Auth hardening" should {

    "register PBKDF2 hashes and log in, rejecting wrong passwords" in new WithApplication {
      val tag = freshTag()
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
        status(bad) must equalTo(UNAUTHORIZED)
      } finally {
        db.deleteFromKey("users", "username", username)
      }
    }

    "still verify legacy SHA-256 rows (bug-compatible hex)" in new WithApplication {
      val tag = freshTag()
      val username = s"contract_legacy_$tag"
      // Replicates helper.User legacy derivation (production rows use that routine).
      def legacyHex(password: String): String = {
        val md = java.security.MessageDigest.getInstance("SHA-256")
        val sb = new StringBuffer
        md.digest(("test-salt" + password + "test-pepper").getBytes("UTF-8")) foreach { b =>
          val hex = Integer.toHexString(0xFF & b)
          if (hex.length == 1) sb.append('0') else sb.append(hex)
        }
        sb.toString
      }
      seed("users", Json.obj("name" -> "Legacy", "email" -> s"legacy_$tag@ejust.edu.eg",
        "username" -> username, "password" -> legacyHex("LegacyPass1!"),
        "access_token" -> s"apLocal_contract_$tag", "external" -> "anyplace",
        "type" -> "user", "owner_id" -> s"${username}_local"))
      try {
        val ok = route(app, FakeRequest(POST, "/api/user/login").withJsonBody(Json.obj(
          "username" -> username, "password" -> "LegacyPass1!"))).get
        status(ok) must equalTo(OK)
        val bad = route(app, FakeRequest(POST, "/api/user/login").withJsonBody(Json.obj(
          "username" -> username, "password" -> "Nope12345!"))).get
        status(bad) must equalTo(UNAUTHORIZED)
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

    "stamp token expiry on login and rotate it on refresh" in new WithApplication {
      val tag = freshTag()
      val username = s"contract_exp_$tag"
      val reg = route(app, FakeRequest(POST, "/api/user/register").withJsonBody(Json.obj(
        "name" -> s"Exp $tag", "email" -> s"exp_$tag@ejust.edu.eg",
        "username" -> username, "password" -> "Password123!"))).get
      status(reg) must equalTo(OK)
      try {
        val login = route(app, FakeRequest(POST, "/api/user/login").withJsonBody(Json.obj(
          "username" -> username, "password" -> "Password123!"))).get
        status(login) must equalTo(OK)
        val token = (extractJson(login) \ "user" \ "access_token").as[String]
        val exp1 = (db.getFromKeyAsJson("users", "username", username) \ "token_expires").as[String].toLong
        exp1 must be_>(System.currentTimeMillis())
        val refresh = route(app, FakeRequest(POST, "/api/user/refresh").withJsonBody(Json.obj(
          "access_token" -> token))).get
        status(refresh) must equalTo(OK)
        val token2 = (extractJson(refresh) \ "user" \ "access_token").as[String]
        token2 must not equalTo token
        val exp2 = (db.getFromKeyAsJson("users", "username", username) \ "token_expires").as[String].toLong
        exp2 must be_>=(exp1)
        // The rotated-out token is dead.
        val stale = route(app, FakeRequest(POST, "/api/user/refresh").withJsonBody(Json.obj(
          "access_token" -> token))).get
        status(stale) must equalTo(UNAUTHORIZED)
      } finally {
        db.deleteFromKey("users", "username", username)
      }
    }

    "reject expired tokens on protected endpoints and refresh" in new WithApplication {
      val tag = freshTag()
      val username = s"contract_expired_$tag"
      val token = s"apLocal_contract_expired_$tag"
      seed("users", Json.obj("name" -> "Old", "email" -> s"old_$tag@ejust.edu.eg",
        "username" -> username, "password" -> "x", "access_token" -> token,
        "external" -> "anyplace", "type" -> "user",
        "owner_id" -> s"${username}_local", "token_expires" -> "1000"))
      try {
        val denied = route(app, FakeRequest(POST, "/api/auth/user/update",
          FakeHeaders(Seq("access_token" -> token, "Content-Type" -> "application/json")),
          AnyContentAsJson(Json.obj("user_id" -> s"${username}_local")))).get
        status(denied) must equalTo(UNAUTHORIZED)
        val noRefresh = route(app, FakeRequest(POST, "/api/user/refresh").withJsonBody(Json.obj(
          "access_token" -> token))).get
        status(noRefresh) must equalTo(UNAUTHORIZED)
      } finally {
        db.deleteFromKey("users", "username", username)
      }
    }

    "forbid moderators changing other users' passwords" in new WithApplication {
      val tag = freshTag()
      val modToken = s"apLocal_contract_mod_$tag"
      val modOwner = s"contract_mod_${tag}_local"
      val victimOwner = s"contract_victim_${tag}_local"
      seed("users", Json.obj("name" -> "Mod", "email" -> s"mod_$tag@ejust.edu.eg",
        "username" -> s"contract_mod_$tag", "password" -> "x",
        "access_token" -> modToken, "external" -> "anyplace",
        "type" -> "moderator", "owner_id" -> modOwner))
      seed("users", Json.obj("name" -> "Victim", "email" -> s"victim_$tag@ejust.edu.eg",
        "username" -> s"contract_victim_$tag", "password" -> "x",
        "access_token" -> s"apLocal_contract_victim_$tag", "external" -> "anyplace",
        "type" -> "user", "owner_id" -> victimOwner))
      try {
        // Moderator lists are boot-cached: refresh so fixture moderator is recognized.
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

    "reject traversal identifiers on radiomap endpoints" in new WithApplication {
      val byFloor = route(app, FakeRequest(POST, "/api/radiomap/space")
        .withJsonBody(Json.obj("buid" -> "../../etc", "floor" -> "0"))).get
      status(byFloor) must equalTo(BAD_REQUEST)

      val byFloors = route(app, FakeRequest(POST, "/api/radiomap/floors")
        .withJsonBody(Json.obj("buid" -> "../../etc", "floors" -> "0"))).get
      status(byFloors) must equalTo(BAD_REQUEST)

      val badFloor = route(app, FakeRequest(POST, "/api/radiomap/floors")
        .withJsonBody(Json.obj("buid" -> "buid_safe", "floors" -> "0 ../../etc"))).get
      status(badFloor) must equalTo(BAD_REQUEST)
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
      val tag = freshTag()
      val buid = s"buid_contract_nc_$tag"
      val puidA = s"puid_contract_nc_a_$tag"
      val puidB = s"puid_contract_nc_b_$tag"
      for (puid <- Seq(puidA, puidB)) {
        seed("pois", Json.obj("puid" -> puid, "buid" -> buid,
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
      val tag = freshTag()
      val cuid = s"cuid_contract_dc_$tag"
      val buidA = s"buid_contract_dc_a_$tag"
      val buidB = s"buid_contract_dc_b_$tag"
      val puidA = s"puid_contract_dc_a_$tag"
      val puidB = s"puid_contract_dc_b_$tag"
      seed("campuses", Json.obj("cuid" -> cuid, "name" -> "DC",
        "description" -> "t", "greeklish" -> "false",
        "buids" -> Json.arr(buidA, buidB), "owner_id" -> "test"))
      seed("pois", Json.obj("puid" -> puidA, "buid" -> buidA,
        "floor_number" -> "0", "name" -> "A",
        "coordinates_lat" -> "30.9501", "coordinates_lon" -> "29.7501",
        "pois_type" -> "Entrance"))
      seed("pois", Json.obj("puid" -> puidB, "buid" -> buidB,
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

  "Wave-0 crash guards" should {

    "400 empty POI search instead of 500" in new WithApplication {
      val response = route(app, FakeRequest(POST, "/api/mapping/pois/search")
        .withJsonBody(Json.obj())).get
      status(response) must equalTo(BAD_REQUEST)
    }

    "400 oversized POI searches before running greeklish expansion" in new WithApplication {
      for (letters <- Seq("a" * 129, (1 to 9).map(_ => "a").mkString(" "))) {
        val response = route(app, FakeRequest(POST, "/api/mapping/pois/search")
          .withJsonBody(Json.obj("buid" -> "x", "letters" -> letters))).get
        status(response) must equalTo(BAD_REQUEST)
      }
    }

    "never 500 malformed access-point ids" in new WithApplication {
      for (body <- Seq(Json.obj(),
        Json.obj("ids" -> 123),
        Json.obj("ids" -> Json.arr("a")),
        Json.obj("ids" -> Json.arr("aa:bb:cc")))) {
        val response = route(app, FakeRequest(POST, "/api/wifi/access_points/ids")
          .withJsonBody(body)).get
        status(response) must not equalTo(INTERNAL_SERVER_ERROR)
      }
    }

    "never 500 malformed position estimates" in new WithApplication {
      for (body <- Seq(
        Json.obj("buid" -> "x", "floor" -> "0", "APs" -> Json.arr(), "algorithm_choice" -> "1"),
        Json.obj("buid" -> "x", "floor" -> "0", "APs" -> "not-json", "algorithm_choice" -> "1"),
        Json.obj("buid" -> "x", "floor" -> "0", "APs" -> "[]", "algorithm_choice" -> "abc"),
        Json.obj("buid" -> "x", "floor" -> "0", "APs" -> "[{\"bssid\":123}]", "algorithm_choice" -> "1"))) {
        val response = route(app, FakeRequest(POST, "/api/position/estimate")
          .withJsonBody(body)).get
        status(response) must not equalTo(INTERNAL_SERVER_ERROR)
      }
    }

    "never 500 malformed floor prediction" in new WithApplication {
      for (body <- Seq(Json.obj(),
        Json.obj("wifi" -> Json.arr("{\"MAC\":\"aa\",\"rss\":\"abc\"}")))) {
        val response = route(app, FakeRequest(POST, "/api/position/predictFloorAlgo1")
          .withJsonBody(body)).get
        status(response) must not equalTo(INTERNAL_SERVER_ERROR)
      }
    }

    "never 500 malformed radiomap queries" in new WithApplication {
      val t1 = route(app, FakeRequest(POST, "/api/radiomap/floors")
        .withJsonBody(Json.obj("buid" -> "x", "floors" -> 123))).get
      status(t1) must not equalTo(INTERNAL_SERVER_ERROR)
      val t2 = route(app, FakeRequest(POST, "/api/radiomap/floor/bbox")
        .withJsonBody(Json.obj("coordinates_lat" -> "35.0", "coordinates_lon" -> "33.0",
          "floor_number" -> "0", "range" -> "99999999999999999999"))).get
      status(t2) must not equalTo(INTERNAL_SERVER_ERROR)
    }

    "never 500 malformed heatmap tiles" in new WithApplication {
      val response = route(app, FakeRequest(POST, "/api/heatmap/floor/average/3/tiles")
        .withJsonBody(Json.obj("buid" -> "x", "floor" -> "0",
          "x" -> 0, "y" -> 0, "z" -> "high"))).get
      status(response) must not equalTo(INTERNAL_SERVER_ERROR)
    }
    "400 Google login without access_token instead of 500" in new WithApplication {
      val response = route(app, FakeRequest(POST, "/api/user/login/google")
        .withJsonBody(Json.obj("external" -> "google"))).get
      status(response) must equalTo(BAD_REQUEST)
    }

    "tolerate corrupt floor docs without 500" in new WithApplication {
      val tag = freshTag()
      val buid = s"buid_contract_cf_$tag"
      seed("spaces", Json.obj("buid" -> buid, "name" -> "CF",
        "description" -> "t", "owner_id" -> "test", "is_published" -> "true"))
      seed("floorplans", Json.obj("fuid" -> s"${buid}_0", "buid" -> buid))
      try {
        val response = route(app, FakeRequest(POST, "/api/mapping/connection/floor/all")
          .withJsonBody(Json.obj("buid" -> buid, "floor_number" -> "0"))).get
        status(response) must not equalTo(INTERNAL_SERVER_ERROR)
      } finally {
        db.deleteFromKey("floorplans", "fuid", s"${buid}_0")
        db.deleteFromKey("spaces", "buid", buid)
      }
    }
  }

  "Ownership binding (IDOR)" should {

    "403 POI update/delete bound to another building" in new WithApplication {
      val tag = freshTag()
      val token = s"apLocal_contract_idor_$tag"
      val owner = s"contract_idor_${tag}_local"
      val buidA = s"buid_idor_a_$tag"
      val buidV = s"buid_idor_v_$tag"
      val puidV = s"puid_idor_v_$tag"
      seed("users", Json.obj("name" -> "O", "email" -> s"o_$tag@ejust.edu.eg",
        "username" -> s"contract_idor_$tag", "password" -> "x",
        "access_token" -> token, "external" -> "anyplace",
        "type" -> "user", "owner_id" -> owner))
      datasources.MongodbDatasource.updateCachedModerators()
      seed("spaces", Json.obj("buid" -> buidA, "name" -> "A",
        "description" -> "t", "owner_id" -> owner, "is_published" -> "true"))
      seed("spaces", Json.obj("buid" -> buidV, "name" -> "V",
        "description" -> "t", "owner_id" -> "someone_else", "is_published" -> "true"))
      seed("pois", Json.obj("puid" -> puidV, "buid" -> buidV,
        "floor_number" -> "0", "name" -> "Victim POI",
        "coordinates_lat" -> "30.1", "coordinates_lon" -> "29.1",
        "pois_type" -> "Room"))
      try {
        val r = route(app, FakeRequest(POST, "/api/auth/mapping/pois/update",
          FakeHeaders(Seq("access_token" -> token, "Content-Type" -> "application/json")),
          AnyContentAsJson(Json.obj("buid" -> buidA, "puid" -> puidV,
            "name" -> "Pwned")))).get
        status(r) must equalTo(FORBIDDEN)
        val r2 = route(app, FakeRequest(POST, "/api/auth/mapping/pois/delete",
          FakeHeaders(Seq("access_token" -> token, "Content-Type" -> "application/json")),
          AnyContentAsJson(Json.obj("buid" -> buidA, "puid" -> puidV)))).get
        status(r2) must equalTo(FORBIDDEN)
      } finally {
        db.deleteFromKey("pois", "puid", puidV)
        db.deleteFromKey("spaces", "buid", buidA)
        db.deleteFromKey("spaces", "buid", buidV)
        db.deleteFromKey("users", "username", s"contract_idor_$tag")
      }
    }

    "400 connection anchored in a third building" in new WithApplication {
      val tag = freshTag()
      val token = s"apLocal_contract_idorc_$tag"
      val owner = s"contract_idorc_${tag}_local"
      val buidA = s"buid_idorc_a_$tag"
      val buidB = s"buid_idorc_b_$tag"
      val buidC = s"buid_idorc_c_$tag"
      seed("users", Json.obj("name" -> "O", "email" -> s"oc_$tag@ejust.edu.eg",
        "username" -> s"contract_idorc_$tag", "password" -> "x",
        "access_token" -> token, "external" -> "anyplace",
        "type" -> "user", "owner_id" -> owner))
      datasources.MongodbDatasource.updateCachedModerators()
      for (b <- Seq(buidA, buidB, buidC)) {
        seed("spaces", Json.obj("buid" -> b, "name" -> b,
          "description" -> "t", "owner_id" -> (if (b == buidC) "someone_else" else owner),
          "is_published" -> "true"))
      }
      seed("pois", Json.obj("puid" -> s"puid_idorc_a_$tag", "buid" -> buidA,
        "floor_number" -> "0", "name" -> "A", "coordinates_lat" -> "30.1",
        "coordinates_lon" -> "29.1", "pois_type" -> "Room"))
      seed("pois", Json.obj("puid" -> s"puid_idorc_b_$tag", "buid" -> buidB,
        "floor_number" -> "0", "name" -> "B", "coordinates_lat" -> "30.2",
        "coordinates_lon" -> "29.2", "pois_type" -> "Room"))
      try {
        val r = route(app, FakeRequest(POST, "/api/auth/mapping/connection/add",
          FakeHeaders(Seq("access_token" -> token, "Content-Type" -> "application/json")),
          AnyContentAsJson(Json.obj("buid" -> buidC, "buid_a" -> buidA,
            "buid_b" -> buidB, "pois_a" -> s"puid_idorc_a_$tag",
            "pois_b" -> s"puid_idorc_b_$tag", "floor_a" -> "0", "floor_b" -> "0",
            "edge_type" -> "hallway", "is_published" -> "true")))).get
        status(r) must equalTo(BAD_REQUEST)
        extractString(r) must contain("endpoint buildings")
      } finally {
        db.deleteFromKey("pois", "puid", s"puid_idorc_a_$tag")
        db.deleteFromKey("pois", "puid", s"puid_idorc_b_$tag")
        for (b <- Seq(buidA, buidB, buidC)) db.deleteFromKey("spaces", "buid", b)
        db.deleteFromKey("users", "username", s"contract_idorc_$tag")
      }
    }
  }

  "Google token claims" should {

    def verifier(implicit app: play.api.Application) =
      app.injector.instanceOf[controllers.helper.User]

    def tokenInfo(aud: String, exp: String, sub: String) = Json.obj(
      "aud" -> aud, "expires_in" -> exp, "sub" -> sub, "email" -> "u@ejust.edu.eg",
      "iss" -> "https://accounts.google.com")

    "accept a live token for our audience" in new WithApplication {
      verifier.validateGoogleTokenInfo(
        tokenInfo("ejust-client", "3600", "gid-1"), Some("ejust-client")) must equalTo("gid-1")
    }

    "reject foreign-audience tokens" in new WithApplication {
      verifier.validateGoogleTokenInfo(
        tokenInfo("evil-client", "3600", "gid-1"), Some("ejust-client")) must beNull
    }

    "reject expired tokens" in new WithApplication {
      verifier.validateGoogleTokenInfo(
        tokenInfo("ejust-client", "0", "gid-1"), Some("ejust-client")) must beNull
    }

    "reject subject-less tokens" in new WithApplication {
      verifier.validateGoogleTokenInfo(
        Json.obj("aud" -> "ejust-client", "expires_in" -> "3600"),
        Some("ejust-client")) must beNull
    }
  }

  "Privacy + product surface" should {

    "never disclose hashes or tokens in the moderator user list" in new WithApplication {
      val tag = freshTag()
      val token = s"apLocal_contract_pii_$tag"
      db.addJson("users", Json.obj("name" -> "PII", "email" -> s"pii_$tag@ejust.edu.eg",
        "username" -> s"contract_pii_$tag", "password" -> "x",
        "access_token" -> token, "external" -> "anyplace",
        "type" -> "moderator", "owner_id" -> s"contract_pii_${tag}_local"))
      datasources.MongodbDatasource.updateCachedModerators()
      try {
        val response = route(app, FakeRequest(POST, "/api/auth/moderator/users/all")
          .withHeaders("access_token" -> token)
          .withJsonBody(Json.obj())).get
        status(response) must equalTo(OK)
        val body = extractString(response)
        body must not contain "password"
        body must not contain token
      } finally {
        db.deleteFromKey("users", "username", s"contract_pii_$tag")
      }
    }

    "report distance and walk time on campus routes" in new WithApplication {
      val tag = freshTag()
      val cuid = s"cuid_contract_dist_$tag"
      val buidA = s"buid_contract_dist_a_$tag"
      val buidB = s"buid_contract_dist_b_$tag"
      val puidA = s"puid_contract_dist_a_$tag"
      val puidB = s"puid_contract_dist_b_$tag"
      db.addJson("campuses", Json.obj("cuid" -> cuid, "name" -> "Dist",
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
        val dist = (json \ "distance_m").as[Long]
        dist must be_>(50L)
        dist must be_<(2000L)
        (json \ "walk_min").as[Int] must be_>=(1)
      } finally {
        db.deleteFromKey("edges", "cuid", s"conn_${puidA}_${puidB}")
        db.deleteFromKey("pois", "puid", puidA)
        db.deleteFromKey("pois", "puid", puidB)
        db.deleteFromKey("campuses", "cuid", cuid)
      }
    }

    "exclude stairs with step_free and say so when disconnected" in new WithApplication {
      val tag = freshTag()
      val cuid = s"cuid_contract_sf_$tag"
      val buid = s"buid_contract_sf_$tag"
      val puidA = s"puid_contract_sf_a_$tag"
      val puidB = s"puid_contract_sf_b_$tag"
      def routeBody() = Json.obj("cuid" -> cuid,
        "pois_from" -> puidA, "pois_to" -> puidB) + ("step_free" -> Json.toJson(true))
      db.addJson("campuses", Json.obj("cuid" -> cuid, "name" -> "SF",
        "description" -> "t", "greeklish" -> "false",
        "buids" -> Json.arr(buid), "owner_id" -> "test"))
      for ((puid, nm) <- Seq((puidA, "A"), (puidB, "B"))) {
        db.addJson("pois", Json.obj("puid" -> puid, "buid" -> buid,
          "floor_number" -> "0", "name" -> nm,
          "coordinates_lat" -> "30.9501", "coordinates_lon" -> "29.7501",
          "pois_type" -> "Entrance"))
      }
      db.addJson("edges", Json.obj("cuid" -> s"conn_${puidA}_${puidB}",
        "pois_a" -> puidA, "pois_b" -> puidB,
        "buid_a" -> buid, "buid_b" -> buid,
        "floor_a" -> "0", "floor_b" -> "0", "buid" -> buid,
        "edge_type" -> "stair", "weight" -> "10.0",
        "is_published" -> "true"))
      try {
        val off = route(app, FakeRequest(POST, "/api/navigation/route/campus")
          .withJsonBody(Json.obj("cuid" -> cuid,
            "pois_from" -> puidA, "pois_to" -> puidB))).get
        status(off) must equalTo(OK)
        val on = route(app, FakeRequest(POST, "/api/navigation/route/campus")
          .withJsonBody(routeBody())).get
        status(on) must equalTo(BAD_REQUEST)
        extractString(on) must contain("step-free")
        // Elevators stay step-free: swap the connector and re-run.
        db.deleteFromKey("edges", "cuid", s"conn_${puidA}_${puidB}")
        db.addJson("edges", Json.obj("cuid" -> s"conn_${puidA}_${puidB}",
          "pois_a" -> puidA, "pois_b" -> puidB,
          "buid_a" -> buid, "buid_b" -> buid,
          "floor_a" -> "0", "floor_b" -> "0", "buid" -> buid,
          "edge_type" -> "elevator", "weight" -> "10.0",
          "is_published" -> "true"))
        val lift = route(app, FakeRequest(POST, "/api/navigation/route/campus")
          .withJsonBody(routeBody())).get
        status(lift) must equalTo(OK)
      } finally {
        db.deleteFromKey("edges", "cuid", s"conn_${puidA}_${puidB}")
        db.deleteFromKey("pois", "puid", puidA)
        db.deleteFromKey("pois", "puid", puidB)
        db.deleteFromKey("campuses", "cuid", cuid)
      }
    }
  }
  }
}
