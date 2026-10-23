package controllers

import datasources.{DatasourceException, ProxyDataSource, SCHEMA}
import models._
import models.oauth.OAuth2Request
import play.api.libs.json.Reads._
import play.api.libs.json._
import play.api.mvc._
import utils.json.VALIDATE
import utils._

import java.io._
import java.text.{NumberFormat, ParseException}
import java.util.Locale
import javax.inject.{Inject, Singleton}
import scala.concurrent.Future
import scala.jdk.CollectionConverters.CollectionHasAsScala

@Singleton
class MapPoiConnectionController @Inject()(cc: ControllerComponents,
                                   pds: ProxyDataSource,
                                   user: helper.User,
                                   actorSystem: akka.actor.ActorSystem)
  extends AbstractController(cc) {
  /** Blocking Mongo/file work stays off Play's default pool (see app.play.conf). */
  private implicit val blockingEc: scala.concurrent.ExecutionContext =
    actorSystem.dispatchers.lookup("contexts.blocking-io-dispatcher")


  def add(): Action[AnyContent] = Action {
    implicit request =>
      def inner(implicit request: Request[AnyContent]): Result = {
        val anyReq = new OAuth2Request(request)
        val apiKey = anyReq.getAccessToken()
        if (apiKey == null) return anyReq.NO_ACCESS_TOKEN()
        if (!anyReq.assertJsonBody()) return RESPONSE.BAD(RESPONSE.ERROR_JSON_PARSE)
        var json = anyReq.getJsonBody()
        LOG.D2("PoiConnection: add: " + Utils.stripJsValueStr(json))
        val checkRequirements = VALIDATE.checkRequirements(json, SCHEMA.fIsPublished, SCHEMA.fPoisA, SCHEMA.fFloorA,
          SCHEMA.fBuidA, SCHEMA.fPoisB, SCHEMA.fFloorB, SCHEMA.fBuidB, SCHEMA.fBuid, SCHEMA.fEdgeType)
        if (checkRequirements != null) return checkRequirements
        val owner_id = user.authorize(apiKey)
        if (owner_id == null) return RESPONSE.UNAUTHORIZED_USER
        json = json.asOpt[JsObject].getOrElse(return RESPONSE.BAD("Body must be a JSON object.")) +
          (SCHEMA.fOwnerId -> Json.toJson(owner_id))
        val buid = (json \ SCHEMA.fBuid).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid buid."))
        val buid1 = (json \ SCHEMA.fBuidA).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid buid_a."))
        val buid2 = (json \ SCHEMA.fBuidB).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid buid_b."))
        try {
          var storedSpace = pds.db.getFromKeyAsJson(SCHEMA.cSpaces, SCHEMA.fBuid, buid1)
          if (storedSpace == null) return RESPONSE.NOT_FOUND("Space not found.")
          if (!user.canAccessSpace(storedSpace, owner_id)) return RESPONSE.UNAUTHORIZED_USER
          storedSpace = pds.db.getFromKeyAsJson(SCHEMA.cSpaces, SCHEMA.fBuid, buid2)
          if (storedSpace == null) return RESPONSE.NOT_FOUND("Space not found.")
          if (!user.canAccessSpace(storedSpace, owner_id)) return RESPONSE.UNAUTHORIZED_USER
          storedSpace = pds.db.getFromKeyAsJson(SCHEMA.cSpaces, SCHEMA.fBuid, buid)
          if (storedSpace == null) return RESPONSE.NOT_FOUND("Space not found.")
        } catch {
          case e: DatasourceException => return RESPONSE.ERROR(e)
        }
        if (buid != buid1 && buid != buid2)
          return RESPONSE.BAD("Connection must belong to one of its endpoint buildings.")
        val edge_type = (json \ SCHEMA.fEdgeType).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid edge type specified."))
        if (edge_type != Connection.EDGE_TYPE_ELEVATOR && edge_type != Connection.EDGE_TYPE_HALLWAY &&
          edge_type != Connection.EDGE_TYPE_ROOM && edge_type != Connection.EDGE_TYPE_OUTDOOR &&
          edge_type != Connection.EDGE_TYPE_STAIR)
          return RESPONSE.BAD("Invalid edge type specified.")
        val pois_a = (json \ SCHEMA.fPoisA).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid pois_a."))
        val pois_b = (json \ SCHEMA.fPoisB).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid pois_b."))
        val floor_a = (json \ SCHEMA.fFloorA).asOpt[String].getOrElse(return RESPONSE.BAD("Invalid floor_a."))
        val floor_b = (json \ SCHEMA.fFloorB).asOpt[String].getOrElse(return RESPONSE.BAD("Invalid floor_b."))
        if (!pds.db.poiByBuidFloorPuid(buid1, floor_a, pois_a))
          return RESPONSE.NOT_FOUND("POI-A not found.")
        if (!pds.db.poiByBuidFloorPuid(buid2, floor_b, pois_b))
          return RESPONSE.NOT_FOUND("POI-B not found.")
        // Duplicate guard: cuid is deterministic per endpoint pair.
        if (pds.db.getFromKeyAsJson(SCHEMA.cEdges, SCHEMA.fConCuid, Connection.getId(pois_a, pois_b)) != null)
          return RESPONSE.BAD("Connection already exists.")
        try {
          // Honor a client-provided weight (restore/import) verbatim so the exact
          // original value is preserved; only recompute from coordinates when no
          // valid weight was supplied.
          val providedWeight = (json \ SCHEMA.fWeight).toOption.flatMap { w =>
            w.asOpt[Double].orElse(w.asOpt[String].flatMap(v =>
              scala.util.Try(v.trim.toDouble).toOption))
          }.filter(_ >= 0.0)
          providedWeight match {
            case Some(w) =>
              json = json.as[JsObject] + (SCHEMA.fWeight -> JsString(java.lang.Double.toString(w)))
            case None =>
              val weight = getConnectionWeight(pois_a, pois_b)
              json = json.as[JsObject] + (SCHEMA.fWeight -> JsString(java.lang.Double.toString(weight)))
          }
          if (edge_type == Connection.EDGE_TYPE_ELEVATOR || edge_type == Connection.EDGE_TYPE_STAIR) {
          }
          val conn = new Connection(json)
          if (!pds.db.addJson(SCHEMA.cEdges, conn.toJson()))
            return RESPONSE.BAD_CANNOT_ADD_CONNECTION
          val res: JsValue = Json.obj(SCHEMA.fConCuid -> conn.getId())
          return RESPONSE.OK(res, "Successfully added new connection.")
        } catch {
          case e: DatasourceException => return RESPONSE.ERROR(e)
        }
      }

      inner(request)
  }

  /**
   * DEPRECATED: NN: Possibly because edges/connection are added or deleted.
   * If the coordinates of a poi (pointed by an edge) change the connection is still unaffected.
   *
   * @return
   */
  @deprecated("NotInUse")
  def connectionUpdate(): Action[AnyContent] = Action {
    implicit request =>

      def inner(implicit request: Request[AnyContent]): Result = {
        val anyReq = new OAuth2Request(request)
        val apiKey = anyReq.getAccessToken()
        if (apiKey == null) return anyReq.NO_ACCESS_TOKEN()
        if (!anyReq.assertJsonBody()) return RESPONSE.BAD(RESPONSE.ERROR_JSON_PARSE)
        var json = anyReq.getJsonBody()
        LOG.D2("PoiConnection: update: " + Utils.stripJsValueStr(json))
        val requiredMissing = JsonUtils.hasProperties(json, SCHEMA.fPoisA, SCHEMA.fPoisB, SCHEMA.fBuidA, SCHEMA.fBuidB)
        if (!requiredMissing.isEmpty) return RESPONSE.MISSING_FIELDS(requiredMissing)
        val owner_id = user.authorize(apiKey)
        if (owner_id == null) return RESPONSE.UNAUTHORIZED_USER
        json = json.asOpt[JsObject].getOrElse(return RESPONSE.BAD("Body must be a JSON object.")) +
          (SCHEMA.fOwnerId -> Json.toJson(owner_id))
        val buid1 = (json \ SCHEMA.fBuidA).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid buid_a."))
        val buid2 = (json \ SCHEMA.fBuidB).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid buid_b."))
        try {
          var storedSpace = pds.db.getFromKeyAsJson(SCHEMA.cSpaces, SCHEMA.fBuid, buid1)
          if (storedSpace == null)
            return RESPONSE.NOT_FOUND("Space not found.")
          if (!user.canAccessSpace(storedSpace, owner_id)) return RESPONSE.UNAUTHORIZED_USER
          storedSpace = pds.db.getFromKeyAsJson(SCHEMA.cSpaces, SCHEMA.fBuid, buid2)
          if (storedSpace == null)
            return RESPONSE.NOT_FOUND("Space not found.")
          if (!user.canAccessSpace(storedSpace, owner_id)) return RESPONSE.UNAUTHORIZED_USER
        } catch {
          case e: DatasourceException => return RESPONSE.ERROR(e)
        }
        try {
          val pois_a = (json \ SCHEMA.fPoisA).asOpt[String].map(_.trim).filter(_.nonEmpty)
            .getOrElse(return RESPONSE.BAD("Invalid pois_a."))
          val pois_b = (json \ SCHEMA.fPoisB).asOpt[String].map(_.trim).filter(_.nonEmpty)
            .getOrElse(return RESPONSE.BAD("Invalid pois_b."))
          val cuid = Connection.getId(pois_a, pois_b)
          var storedConn = pds.db.getFromKeyAsJson(SCHEMA.cEdges, SCHEMA.fConCuid, cuid)
          if (storedConn == null)
            return RESPONSE.NOT_FOUND("Connection not found.")
          if ((json \ SCHEMA.fIsPublished).asOpt[String].exists(s => s == "true" || s == "false")) {
            storedConn = storedConn.as[JsObject] + (SCHEMA.fIsPublished -> JsString((json \ SCHEMA.fIsPublished).as[String]))
          }
          if ((json \ SCHEMA.fEdgeType).asOpt[String].isDefined) {
            val edge_type = (json \ SCHEMA.fEdgeType).asOpt[String].map(_.trim).filter(_.nonEmpty)
              .getOrElse(return RESPONSE.BAD("Invalid edge type specified."))
            if (edge_type != Connection.EDGE_TYPE_ELEVATOR && edge_type != Connection.EDGE_TYPE_HALLWAY &&
              edge_type != Connection.EDGE_TYPE_ROOM && edge_type != Connection.EDGE_TYPE_OUTDOOR &&
              edge_type != Connection.EDGE_TYPE_STAIR)
              return RESPONSE.BAD("Invalid edge type specified.")
            storedConn = storedConn.as[JsObject] + (SCHEMA.fEdgeType -> JsString(edge_type))
          }
          val conn = new Connection(storedConn)
          if (!pds.db.replaceJsonDocument(SCHEMA.cEdges, SCHEMA.fConCuid, conn.getId(), conn.toJson().toString))
            return RESPONSE.BAD("Connection could not be updated.")
          return RESPONSE.OK("Successfully updated connection.")
        } catch {
          case e: DatasourceException => return RESPONSE.ERROR(e)
        }
      }

      inner(request)
  }

  def delete(): Action[AnyContent] = Action {
    implicit request =>
      def inner(implicit request: Request[AnyContent]): Result = {
        LOG.D2("PoiConnection: delete")
        val anyReq = new OAuth2Request(request)
        val apiKey = anyReq.getAccessToken()
        if (apiKey == null) return anyReq.NO_ACCESS_TOKEN()
        if (!anyReq.assertJsonBody()) return RESPONSE.BAD(RESPONSE.ERROR_JSON_PARSE)
        var json = anyReq.getJsonBody()
        val checkRequirements = VALIDATE.checkRequirements(json, SCHEMA.fPoisA, SCHEMA.fPoisB, SCHEMA.fBuidA, SCHEMA.fBuidB)
        if (checkRequirements != null) return checkRequirements
        val owner_id = user.authorize(apiKey)
        if (owner_id == null) return RESPONSE.UNAUTHORIZED_USER
        json = json.asOpt[JsObject].getOrElse(return RESPONSE.BAD("Body must be a JSON object.")) +
          (SCHEMA.fOwnerId -> Json.toJson(owner_id))
        val buid1 = (json \ SCHEMA.fBuidA).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid buid_a."))
        val buid2 = (json \ SCHEMA.fBuidB).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid buid_b."))
        try {
          var storedSpace = pds.db.getFromKeyAsJson(SCHEMA.cSpaces, SCHEMA.fBuid, buid1)
          if (storedSpace == null) return RESPONSE.BAD_CANNOT_RETRIEVE("SpaceA")
          if (!user.canAccessSpace(storedSpace, owner_id)) return RESPONSE.UNAUTHORIZED_USER
          storedSpace = pds.db.getFromKeyAsJson(SCHEMA.cSpaces, SCHEMA.fBuid, buid2)
          if (storedSpace == null) return RESPONSE.BAD_CANNOT_RETRIEVE("SpaceB")
          if (!user.canAccessSpace(storedSpace, owner_id)) return RESPONSE.UNAUTHORIZED_USER
        } catch {
          case e: DatasourceException => return RESPONSE.ERROR(e)
        }
        val pois_a = (json \ SCHEMA.fPoisA).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid pois_a."))
        val pois_b = (json \ SCHEMA.fPoisB).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid pois_b."))
        try {
          val cuid = Connection.getId(pois_a, pois_b)
          // Verify connection endpoint access.
          val storedConn = pds.db.getFromKeyAsJson(SCHEMA.cEdges, SCHEMA.fConCuid, cuid)
          if (storedConn == null) return RESPONSE.NOT_FOUND("Connection not found.")
          for (bk <- Seq(SCHEMA.fBuidA, SCHEMA.fBuidB)) {
            val eb = (storedConn \ bk).asOpt[String].getOrElse("")
            val esp = pds.db.getFromKeyAsJson(SCHEMA.cSpaces, SCHEMA.fBuid, eb)
            if (esp == null || !user.canAccessSpace(esp, owner_id)) return RESPONSE.UNAUTHORIZED_USER
          }
          val all_items_failed = pds.db.deleteAllByConnection(cuid)
          if (all_items_failed.size > 0) {
            val obj: JsValue = Json.obj("ids" -> all_items_failed.asScala)
            return RESPONSE.BAD(obj, "Some items related to the deleted connection could not be deleted: " +
              all_items_failed.size + " items.")
          }
          return RESPONSE.OK("Successfully deleted everything related to the connection.")
        } catch {
          case e: DatasourceException => RESPONSE.ERROR(e)
        }
      }

      inner(request)
  }

  def byFloor(): Action[AnyContent] = Action.async {
    implicit request =>
      def inner(implicit request: Request[AnyContent]): Result = {
        val anyReq = new OAuth2Request(request)
        if (!anyReq.assertJsonBody()) return RESPONSE.BAD(RESPONSE.ERROR_JSON_PARSE)
        val json = anyReq.getJsonBody()
        LOG.D2("PoiConnection: byFloor: " + Utils.stripJsValueStr(json))
        val checkRequirements = VALIDATE.checkRequirements(json, SCHEMA.fBuid, SCHEMA.fFloorNumber)
        if (checkRequirements != null) return checkRequirements
        val buid = (json \ SCHEMA.fBuid).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid buid."))
        val floorNum = (json \ SCHEMA.fFloorNumber).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid floor_number."))
        try {
          val storedSpace = pds.db.getFromKeyAsJson(SCHEMA.cSpaces, SCHEMA.fBuid, buid)
          if (storedSpace == null) return RESPONSE.NOT_FOUND("Space not found.")
          val storedFloors = pds.db.floorsByBuildingAsJson(buid)
          var floorExists = false
          for (floor <- storedFloors.asScala)
            if ((floor \ SCHEMA.fFloorNumber).asOpt[String].contains(floorNum))
              floorExists = true
          if (!floorExists) return RESPONSE.NOT_FOUND("Floor not found.")

          val pois = pds.db.connectionsByBuildingFloorAsJson(buid, floorNum)
          val res: JsValue = Json.obj("connections" -> pois)
          try {
            RESPONSE.gzipJsonOk(res.toString)
          } catch {
            case ioe: IOException => return RESPONSE.OK(res, "Successfully retrieved all pois from floor " + floorNum +
              ".")
          }
        } catch {
          case e: DatasourceException => return RESPONSE.ERROR(e)
        }
      }

      Future { inner(request) }(blockingEc)
  }

  /**
   * Retrieve all the pois of a building/floor combination.
   *
   * @return
   */
  def byFloorsAll: Action[AnyContent] = Action.async {
    implicit request =>

      def inner(implicit request: Request[AnyContent]): Result = {
        val anyReq = new OAuth2Request(request)
        if (!anyReq.assertJsonBody())
          return RESPONSE.BAD(RESPONSE.ERROR_JSON_PARSE)
        val json = anyReq.getJsonBody()
        LOG.I("PoiConnection: byFloorsAll: " + Utils.stripJsValueStr(json))
        val checkRequirements = VALIDATE.checkRequirements(json, SCHEMA.fBuid)
        if (checkRequirements != null) return checkRequirements
        val buid = (json \ SCHEMA.fBuid).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid buid."))
        try {
          val storedSpace = pds.db.getFromKeyAsJson(SCHEMA.cSpaces, SCHEMA.fBuid, buid)
          if (storedSpace == null) return RESPONSE.NOT_FOUND("Space not found.")
          val pois = pds.db.connectionsByBuildingAllFloorsAsJson(buid)
          val res: JsValue = Json.obj("connections" -> pois)
          try
            RESPONSE.gzipJsonOk(res.toString)
          catch {
            case ioe: IOException =>
              return RESPONSE.OK(res, "Successfully retrieved all pois from all floors .")
          }
        } catch {
          case e: DatasourceException =>
            return RESPONSE.ERROR(e)
        }
      }

      Future { inner(request) }(blockingEc)
  }

  private def getConnectionWeight(pois_a: String, pois_b: String) = {
    var lat_a = 0.0
    var lon_a = 0.0
    var lat_b = 0.0
    var lon_b = 0.0
    val nf = NumberFormat.getInstance(Locale.ENGLISH)
    val pa = pds.db.getFromKeyAsJson(SCHEMA.cPOIS, SCHEMA.fPuid, pois_a)
    if (pa == null) {
      lat_a = 0.0
      lon_a = 0.0
    } else try {
      lat_a = nf.parse((pa \ SCHEMA.fCoordinatesLat).asOpt[String].getOrElse("0")).doubleValue()
      lon_a = nf.parse((pa \ SCHEMA.fCoordinatesLon).asOpt[String].getOrElse("0")).doubleValue()
    } catch {
      case _: ParseException => LOG.E("getConnectionWeight: unparsable POI-A coordinates.")
      case _: Exception => LOG.E("getConnectionWeight: unreadable POI-A coordinates.")
    }
    val pb = pds.db.getFromKeyAsJson(SCHEMA.cPOIS, SCHEMA.fPuid, pois_b)
    if (pb == null) {
      lat_b = 0.0
      lon_b = 0.0
    } else try {
      lat_b = nf.parse((pb \ SCHEMA.fCoordinatesLat).asOpt[String].getOrElse("0")).doubleValue()
      lon_b = nf.parse((pb \ SCHEMA.fCoordinatesLon).asOpt[String].getOrElse("0")).doubleValue()
    } catch {
      case _: ParseException => LOG.E("getConnectionWeight: unparsable POI-B coordinates.")
      case _: Exception => LOG.E("getConnectionWeight: unreadable POI-B coordinates.")
    }
    GeoPoint.getDistanceBetweenPoints(lat_a, lon_a, lat_b, lon_b, "K")
  }
}
