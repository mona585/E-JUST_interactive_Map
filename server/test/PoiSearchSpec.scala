import datasources.MongodbDatasource
import org.specs2.mutable.Specification

class PoiSearchSpec extends Specification {

  "greeklish expansion" should {

    "bound pathological variant growth" in {
      val datasource = new MongodbDatasource()
      datasource.greeklishTogreekList("e" * 128).size must beLessThanOrEqualTo(512)
    }
  }
}
