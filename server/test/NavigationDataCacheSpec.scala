import org.specs2.mutable.Specification
import utils.NavigationDataCache

import java.util.{ArrayList, HashMap}

class NavigationDataCacheSpec extends Specification {

  private def pois(ids: String*): ArrayList[HashMap[String, String]] = {
    val list = new ArrayList[HashMap[String, String]]()
    ids.foreach { id =>
      val m = new HashMap[String, String]()
      m.put("puid", id)
      list.add(m)
    }
    list
  }

  "NavigationDataCache" should {

    "load a key once and reuse the snapshot" in {
      NavigationDataCache.clear()
      var loads = 0
      val first = NavigationDataCache.getOrLoad("k") {
        loads += 1
        (pois("a"), pois("b"))
      }
      val second = NavigationDataCache.getOrLoad("k") {
        loads += 1
        (pois("c"), pois("d"))
      }
      loads must equalTo(1)
      first.pois must beTheSameAs(second.pois)
      first.edges must beTheSameAs(second.edges)
    }

    "clear invalidates every snapshot" in {
      NavigationDataCache.clear()
      NavigationDataCache.getOrLoad("k")((pois("a"), pois("b")))
      NavigationDataCache.size() must equalTo(1)
      NavigationDataCache.clear()
      NavigationDataCache.size() must equalTo(0)
      NavigationDataCache.get("k") must beNone
    }
  }
}
