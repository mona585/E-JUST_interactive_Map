import org.specs2.matcher.MatchResult
import org.specs2.mutable.Specification
import play.api.http.HeaderNames
import play.api.libs.json.Json
import play.api.test.FakeRequest
import play.api.test.Helpers._
import utils.RESPONSE

/**
 * API responses must be JSON not only in body but also in content type.
 * Several legacy clients and proxies branch on Content-Type, so a plain-text
 * JSON body is an observable contract violation.
 */
class ResponseSpec extends Specification {

  private def assertJson(result: play.api.mvc.Result, expectedStatus: Int, expectedValue: Int): MatchResult[Int] = {
    result.header.status must equalTo(expectedStatus)
    result.body.contentType must
      beSome.which(_.toLowerCase.startsWith("application/json"))
    (contentAsJson(scala.concurrent.Future.successful(result)) \ "status_code").as[Int] must
      equalTo(expectedValue)
  }

  "RESPONSE envelopes" should {

    "emit application/json for success" in {
      val result = RESPONSE.OK(Json.obj("value" -> 1), "ok")
      assertJson(result, OK, 200)
      (contentAsJson(scala.concurrent.Future.successful(result)) \ "value").as[Int] must equalTo(1)
    }

    "emit application/json for bad requests" in {
      assertJson(RESPONSE.BAD("bad"), BAD_REQUEST, 400)
    }

    "emit application/json for forbidden responses" in {
      assertJson(RESPONSE.FORBIDDEN("denied"), FORBIDDEN, 403)
    }

    "emit application/json for unauthorized responses" in {
      assertJson(RESPONSE.UNAUTHORIZED("token required"), UNAUTHORIZED, 401)
    }

    "emit application/json for not-found responses" in {
      assertJson(RESPONSE.NOT_FOUND("missing"), NOT_FOUND, 404)
    }

    "emit application/json for internal errors" in {
      assertJson(RESPONSE.ERROR_INTERNAL("failed"), INTERNAL_SERVER_ERROR, 500)
    }

    "not leak exception details in internal errors" in {
      val result = RESPONSE.ERROR(new RuntimeException("secret detail"))
      assertJson(result, INTERNAL_SERVER_ERROR, 500)
      val message = (contentAsJson(scala.concurrent.Future.successful(result)) \ "message").as[String]
      message must not(beMatching(".*secret detail.*"))
    }

    "not leak tagged exception details in internal errors" in {
      val result = RESPONSE.ERROR("lookup", new RuntimeException("secret detail"))
      assertJson(result, INTERNAL_SERVER_ERROR, 500)
      val message = (contentAsJson(scala.concurrent.Future.successful(result)) \ "message").as[String]
      message must not(beMatching(".*secret detail.*"))
    }

    "preserve caller-supplied JSON fields" in {
      val result = RESPONSE.OK(Json.obj("user" -> Json.obj("name" -> "Ada")), "ok")
      val body = contentAsJson(scala.concurrent.Future.successful(result))
      (body \ "user" \ "name").as[String] must equalTo("Ada")
      (body \ "status").as[String] must equalTo("success")
    }

    "emit application/json for gzipped responses" in {
      implicit val request = FakeRequest().withHeaders(HeaderNames.ACCEPT_ENCODING -> "gzip")
      val result = RESPONSE.gzipJsonOk("""{"ok":true}""")
      result.body.contentType must
        beSome.which(_.toLowerCase.startsWith("application/json"))
    }

    "leave small JSON bodies uncompressed" in {
      implicit val request = FakeRequest().withHeaders(HeaderNames.ACCEPT_ENCODING -> "gzip")
      val result = RESPONSE.gzipJsonOk("""{"ok":true}""")
      result.header.headers.get("Content-Encoding") must beNone
    }

    "compress large JSON bodies" in {
      implicit val request = FakeRequest().withHeaders(HeaderNames.ACCEPT_ENCODING -> "gzip")
      val result = RESPONSE.gzipJsonOk("""{"items":[""" + ("x" * 2048) + """]}""")
      result.header.headers.get("Content-Encoding") must beSome("gzip")
    }

    "skip compression when the client does not accept gzip" in {
      implicit val request = FakeRequest()
      val result = RESPONSE.gzipJsonOk("""{"items":[""" + ("x" * 2048) + """]}""")
      result.header.headers.get("Content-Encoding") must beNone
      result.body.contentType must
        beSome.which(_.toLowerCase.startsWith("application/json"))
    }
  }
}
