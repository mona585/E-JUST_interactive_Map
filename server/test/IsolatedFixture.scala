import org.specs2.mutable.Specification
import play.api.libs.json.JsValue
import play.api.test._
/** Shared Mongo fixture: UUID tags, idempotent seed with pre-cleanup, no Thread.sleep. */
trait IsolatedFixture {

  def db(implicit app: play.api.Application): datasources.ProxyDataSource =
    app.injector.instanceOf[datasources.ProxyDataSource]

  def freshTag(): String = java.util.UUID.randomUUID().toString.takeRight(12)

  /** Idempotent fixture write with pre-cleanup. */
  def seed(col: String, doc: JsValue)
      (implicit app: play.api.Application): Boolean = {
    val key = col match {
      case "campuses" | "edges" => "cuid"
      case "pois" => "puid"
      case "users" => "username"
      case "spaces" => "buid"
      case "floorplans" => "fuid"
      case _ => return db.addJson(col, doc)
    }
    (doc \ key).asOpt[String] match {
      case Some(value) =>
        db.deleteFromKey(col, key, value)
        db.addJson(col, doc)
      case None => db.addJson(col, doc)
    }
  }
}
