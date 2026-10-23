import org.specs2.mutable.Specification
import play.api.test.FakeRequest
import play.api.test.Helpers._
import scala.concurrent.Await
import scala.concurrent.duration._

/**
 * Error responses must not regress to text/plain or leak exception internals.
 * The ErrorHandler is the last line of defence for uncaught API failures.
 */
class ErrorHandlerSpec extends Specification {

  private val handler = new ErrorHandler()
  private val timeout = 5.seconds

  "ErrorHandler API errors" should {

    "return JSON content type for client errors under /api" in {
      val result = Await.result(
        handler.onClientError(FakeRequest(GET, "/api/does-not-exist"), NOT_FOUND, "missing"),
        timeout)
      result.header.status must equalTo(NOT_FOUND)
      result.body.contentType must
        beSome.which(_.toLowerCase.startsWith("application/json"))
      (contentAsJson(scala.concurrent.Future.successful(result)) \ "status").as[String] must
        equalTo("error")
    }

    "return JSON content type for server errors under /api" in {
      val result = Await.result(
        handler.onServerError(FakeRequest(GET, "/api/boom"), new RuntimeException("secret detail")),
        timeout)
      result.header.status must equalTo(INTERNAL_SERVER_ERROR)
      result.body.contentType must
        beSome.which(_.toLowerCase.startsWith("application/json"))
      val body = contentAsString(scala.concurrent.Future.successful(result))
      body must not contain("secret detail")
      body must contain("Internal error")
    }

    "keep non-API client errors as plain text" in {
      val result = Await.result(
        handler.onClientError(FakeRequest(GET, "/viewer/missing"), NOT_FOUND, "missing"),
        timeout)
      result.body.contentType must
        beSome.which(_.toLowerCase.startsWith("text/plain"))
      contentAsString(scala.concurrent.Future.successful(result)) must contain("Client Error")
    }

    "report the actual client-error status" in {
      val result = Await.result(
        handler.onClientError(FakeRequest(GET, "/viewer/bad"), BAD_REQUEST, "bad"),
        timeout)
      contentAsString(scala.concurrent.Future.successful(result)) must contain("Client Error: 400")
    }

    "not leak exception details from non-API server errors" in {
      val result = Await.result(
        handler.onServerError(FakeRequest(GET, "/viewer/boom"),
          new RuntimeException("secret detail")),
        timeout)
      result.body.contentType must
        beSome.which(_.toLowerCase.startsWith("text/plain"))
      val body = contentAsString(scala.concurrent.Future.successful(result))
      body must not contain("secret detail")
      body must contain("Internal Server Error")
    }
  }
}
