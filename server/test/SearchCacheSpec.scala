import org.specs2.mutable.Specification
import play.api.libs.json.Json
import utils.SearchCache

class SearchCacheSpec extends Specification {

  sequential

  "SearchCache" should {
    "return a cached result until it is cleared" in {
      SearchCache.clear()
      val results = List(Json.obj("puid" -> "poi_1"))
      SearchCache.put("cuid|buid|false|lab", results)
      SearchCache.get("cuid|buid|false|lab") must beSome(results)
      SearchCache.clear()
      SearchCache.get("cuid|buid|false|lab") must beNone
    }

    "bound the number of cached queries" in {
      SearchCache.clear()
      for (i <- 1 to 100) {
        SearchCache.put("key-" + i, List(Json.obj("puid" -> ("poi_" + i))))
      }
      SearchCache.size() must beLessThanOrEqualTo(64)
      SearchCache.get("key-100") must beSome
      SearchCache.get("key-1") must beNone
    }
  }
}
