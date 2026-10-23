import org.specs2.mutable.Specification
import utils.AccessPointIdsCache

import java.io.ByteArrayInputStream
import java.nio.charset.StandardCharsets

class AccessPointIdsCacheSpec extends Specification {

  private def stream(json: String) =
    new ByteArrayInputStream(json.getBytes(StandardCharsets.UTF_8))

  private val idsJson =
    """[
      |{"mac":"00:00:00","id":"Vendor A"},
      |{"mac":"AA:BB:CC","id":"Vendor B"},
      |{"mac":"AA:BB:CC","id":"Duplicate ignored"}
      |]""".stripMargin

  sequential

  "AccessPointIdsCache" should {
    "match a three-octet OUI prefix" in {
      AccessPointIdsCache.clear()
      val out = AccessPointIdsCache.lookup(List("00:00:00:11:22:33"), () => stream(idsJson))
      out must beSome(List("Vendor A"))
    }

    "match case-insensitively" in {
      AccessPointIdsCache.clear()
      val out = AccessPointIdsCache.lookup(List("aa:bb:cc:11:22:33"), () => stream(idsJson))
      out must beSome(List("Vendor B"))
    }

    "return N/A for an unknown prefix" in {
      AccessPointIdsCache.clear()
      val out = AccessPointIdsCache.lookup(List("11:22:33:44:55:66"), () => stream(idsJson))
      out must beSome(List("N/A"))
    }

    "return None when the source is missing" in {
      AccessPointIdsCache.clear()
      AccessPointIdsCache.lookup(List("00:00:00"), () => null) must beNone
    }

    "parse the file only once" in {
      AccessPointIdsCache.clear()
      var opens = 0
      def supplier() = { opens += 1; stream(idsJson) }
      AccessPointIdsCache.lookup(List("00:00:00"), supplier)
      AccessPointIdsCache.lookup(List("00:00:00"), supplier)
      opens must equalTo(1)
    }
  }
}
