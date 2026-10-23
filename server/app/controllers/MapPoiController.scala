package controllers

import datasources.{DatasourceException, ProxyDataSource, SCHEMA}
import models._
import models.oauth.OAuth2Request
import play.api.libs.json.Reads._
import play.api.libs.json._
import play.api.mvc._
import utils.json.VALIDATE
import utils.json.VALIDATE.String
import utils._
import java.io._
import javax.inject.{Inject, Singleton}
import scala.concurrent.Future
import scala.jdk.CollectionConverters.CollectionHasAsScala
@Singleton
class MapPoiController @Inject()(cc: ControllerComponents,
                                           pds: ProxyDataSource,
                                           user: helper.User,
                                           actorSystem: akka.actor.ActorSystem)
  extends AbstractController(cc) {
  /** Blocking Mongo/file work stays off Play's default pool (see app.play.conf). */
  private implicit val blockingEc: scala.concurrent.ExecutionContext =
    actorSystem.dispatchers.lookup("contexts.blocking-io-dispatcher")


  private val MAX_SEARCH_QUERY_LENGTH = 128
  private val MAX_SEARCH_WORDS = 8

  def add(): Action[AnyContent] = Action {
    implicit request =>
      def inner(request: Request[AnyContent]): Result = {
        val anyReq = new OAuth2Request(request)

        val apiKey = anyReq.getAccessToken()
        if (apiKey == null) return anyReq.NO_ACCESS_TOKEN()

        if (!anyReq.assertJsonBody()) return RESPONSE.BAD(RESPONSE.ERROR_JSON_PARSE)
        var json = anyReq.getJsonBody()
        LOG.D2("POI: add: " + Utils.stripJsValueStr(json))
        val checkRequirements = VALIDATE.checkRequirements(json, SCHEMA.fIsPublished, SCHEMA.fBuid, SCHEMA.fFloorName,
          SCHEMA.fFloorNumber, SCHEMA.fName, SCHEMA.fPoisType, SCHEMA.fIsDoor, SCHEMA.fIsBuildingEntrance, SCHEMA.fCoordinatesLat, SCHEMA.fCoordinatesLon)
        if (checkRequirements != null) return checkRequirements
        val owner_id = user.authorize(apiKey)
        if (owner_id == null) return RESPONSE.UNAUTHORIZED_USER
        json = json.asOpt[JsObject].getOrElse(return RESPONSE.BAD("Body must be a JSON object.")) +
          (SCHEMA.fOwnerId -> Json.toJson(owner_id)) - SCHEMA.fAccessToken
        val buid = (json \ SCHEMA.fBuid).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid buid."))
        val floorNum = (json \ SCHEMA.fFloorNumber).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid floor_number."))
        try {
          val storedSpace = pds.db.getFromKeyAsJson(SCHEMA.cSpaces, SCHEMA.fBuid, buid)
          if (storedSpace == null) return RESPONSE.NOT_FOUND("Space not found.")
          if (!user.canAccessSpace(storedSpace, owner_id)) return RESPONSE.UNAUTHORIZED_USER
          // No orphan POIs: the floor must exist in this building.
          val fuid = Floor.getId(buid, floorNum)
          if (pds.db.getFromKeyAsJson(SCHEMA.cFloorplans, SCHEMA.fFuid, fuid) == null)
            return RESPONSE.NOT_FOUND("Floor not found.")
        } catch {
          case e: DatasourceException => return RESPONSE.ERROR(e)
        }
        try {
          val poi = new Poi(json)
          if (!pds.db.addJson(SCHEMA.cPOIS, poi.toGeoJson())) return RESPONSE.BAD_CANNOT_RETRIEVE_POI
          SearchCache.clear()
          val res: JsValue = Json.obj(SCHEMA.fPuid -> poi.getId())
          return RESPONSE.OK(res, "Successfully added POI.")
        } catch {
          case e: DatasourceException => return RESPONSE.ERROR(e)
        }
      }

      inner(request)
  }

  def update(): Action[AnyContent] = Action {
    implicit request =>
      def inner(request: Request[AnyContent]): Result = {
        val anyReq = new OAuth2Request(request)
        val apiKey = anyReq.getAccessToken()
        if (apiKey == null) return anyReq.NO_ACCESS_TOKEN()
        if (!anyReq.assertJsonBody()) return RESPONSE.BAD(RESPONSE.ERROR_JSON_PARSE)
        var json = anyReq.getJsonBody()
        LOG.D2("POI: update: " + Utils.stripJsValueStr(json))
        val checkRequirements = VALIDATE.checkRequirements(json, SCHEMA.fPuid, SCHEMA.fBuid)
        if (checkRequirements != null) return checkRequirements
        val owner_id = user.authorize(apiKey)
        if (owner_id == null) return RESPONSE.UNAUTHORIZED_USER
        json = json.asOpt[JsObject].getOrElse(return RESPONSE.BAD("Body must be a JSON object.")) +
          (SCHEMA.fOwnerId -> Json.toJson(owner_id))
        val puid = (json \ SCHEMA.fPuid).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid puid."))
        val buid = (json \ SCHEMA.fBuid).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid buid."))
        try {
          val storedSpace = pds.db.getFromKeyAsJson(SCHEMA.cSpaces, SCHEMA.fBuid, buid)
          if (storedSpace == null) return RESPONSE.NOT_FOUND("Space not found.")
          if (!user.canAccessSpace(storedSpace, owner_id)) return RESPONSE.UNAUTHORIZED_USER
        } catch {
          case e: DatasourceException => return RESPONSE.ERROR(e)
        }
        try {
          var storedPoi = pds.db.getFromKeyAsJson(SCHEMA.cPOIS, SCHEMA.fPuid, puid)
          if (storedPoi == null) return RESPONSE.NOT_FOUND("POI not found.")
          // Verify POI building match.
          if ((storedPoi \ SCHEMA.fBuid).asOpt[String].getOrElse("") != buid)
            return RESPONSE.FORBIDDEN("POI belongs to a different space.")
          if ((json \ SCHEMA.fIsPublished).asOpt[String].exists(s => s == "true" || s == "false")
          ) {
            storedPoi = storedPoi.as[JsObject] + (SCHEMA.fIsPublished -> JsString((json \ SCHEMA.fIsPublished).as[String]))
          }
          if ((json \ SCHEMA.fName).asOpt[String].exists(_.trim.nonEmpty))
            storedPoi = storedPoi.as[JsObject] + (SCHEMA.fName -> JsString((json \ SCHEMA.fName).as[String]))
          if ((json \ SCHEMA.fDescription).asOpt[String].isDefined)
            storedPoi = storedPoi.as[JsObject] + (SCHEMA.fDescription -> JsString((json \ SCHEMA.fDescription).as[String]))
          if ((json \ SCHEMA.fURL).asOpt[String].isDefined)
            storedPoi = storedPoi.as[JsObject] + (SCHEMA.fURL -> JsString((json \ SCHEMA.fURL).as[String]))
          if ((json \ SCHEMA.fPoisType).asOpt[String].isDefined)
            storedPoi = storedPoi.as[JsObject] + (SCHEMA.fPoisType -> JsString((json \ SCHEMA.fPoisType).as[String]))
          if ((json \ SCHEMA.fIsDoor).asOpt[String].exists(s => s == "true" || s == "false")) {
            storedPoi = storedPoi.as[JsObject] + (SCHEMA.fIsDoor -> JsString((json \ SCHEMA.fIsDoor).as[String]))
          }
          if ((json \ SCHEMA.fIsBuildingEntrance).asOpt[String].exists(s => s == "true" || s == "false")) {
            storedPoi = storedPoi.as[JsObject] + (SCHEMA.fIsBuildingEntrance, JsString((json \ SCHEMA.fIsBuildingEntrance).as[String]))
          }
          if ((json \ SCHEMA.fImage).asOpt[String].isDefined)
            storedPoi = storedPoi.as[JsObject] + (SCHEMA.fImage, JsString((json \ SCHEMA.fImage).as[String]))
          if ((json \ SCHEMA.fCoordinatesLat).asOpt[String].isDefined)
            storedPoi = storedPoi.as[JsObject] + (SCHEMA.fCoordinatesLat, JsString((json \ SCHEMA.fCoordinatesLat).as[String]))
          if ((json \ SCHEMA.fCoordinatesLon).asOpt[String].isDefined)
            storedPoi = storedPoi.as[JsObject] + (SCHEMA.fCoordinatesLon, JsString((json \ SCHEMA.fCoordinatesLon).as[String]))
          val poi = new Poi(storedPoi)
          if (!pds.db.replaceJsonDocument(SCHEMA.cPOIS, SCHEMA.fPuid, poi.getId(), poi.toGeoJsonStr()))
            return RESPONSE.BAD("Poi could not be updated.")
          SearchCache.clear()
          return RESPONSE.OK("Successfully updated poi.")
        } catch {
          case e: DatasourceException => return RESPONSE.ERROR(e)
        }
      }

      inner(request)
  }

  def delete(): Action[AnyContent] = Action {
    implicit request =>
      def inner(request: Request[AnyContent]): Result = {
        val anyReq = new OAuth2Request(request)
        val apiKey = anyReq.getAccessToken()
        if (apiKey == null) return anyReq.NO_ACCESS_TOKEN()
        if (!anyReq.assertJsonBody()) return RESPONSE.BAD(RESPONSE.ERROR_JSON_PARSE)
        var json = anyReq.getJsonBody()
        LOG.D2("POI: delete: " + Utils.stripJsValueStr(json))
        val checkRequirements = VALIDATE.checkRequirements(json, SCHEMA.fPuid, SCHEMA.fBuid)
        if (checkRequirements != null) return checkRequirements
        val owner_id = user.authorize(apiKey)
        if (owner_id == null) return RESPONSE.UNAUTHORIZED_USER
        json = json.asOpt[JsObject].getOrElse(return RESPONSE.BAD("Body must be a JSON object.")) +
          (SCHEMA.fOwnerId -> Json.toJson(owner_id))
        val buid = (json \ SCHEMA.fBuid).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid buid."))
        val puid = (json \ SCHEMA.fPuid).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid puid."))
        try {
          val storedSpace = pds.db.getFromKeyAsJson(SCHEMA.cSpaces, SCHEMA.fBuid, buid)
          if (storedSpace == null) return RESPONSE.NOT_FOUND("Space not found.")
          if (!user.canAccessSpace(storedSpace, owner_id)) return RESPONSE.UNAUTHORIZED_USER
        } catch {
          case e: DatasourceException => return RESPONSE.ERROR(e)
        }
        try {
          val storedPoi = pds.db.getFromKeyAsJson(SCHEMA.cPOIS, SCHEMA.fPuid, puid)
          if (storedPoi == null) return RESPONSE.NOT_FOUND("POI not found.")
          // Verify POI building match.
          if ((storedPoi \ SCHEMA.fBuid).asOpt[String].getOrElse("") != buid)
            return RESPONSE.FORBIDDEN("POI belongs to a different space.")
          val all_items_failed = pds.db.deleteAllByPoi(puid)
          SearchCache.clear()
          if (all_items_failed.size > 0) {
            val res = Json.obj("ids" -> all_items_failed.asScala)
            return RESPONSE.BAD(res, "Some items related to the deleted poi could not be deleted: " +
              all_items_failed.size +
              " items.")
          }
          return RESPONSE.OK("Successfully deleted everything related to the poi.")
        } catch {
          case e: DatasourceException => return RESPONSE.ERROR(e)
        }

      }

      inner(request)
  }

  def byFloor(): Action[AnyContent] = Action.async {
    implicit request =>
      def inner(request: Request[AnyContent]): Result = {
        val anyReq = new OAuth2Request(request)
        if (!anyReq.assertJsonBody()) return RESPONSE.BAD(RESPONSE.ERROR_JSON_PARSE)
        val json = anyReq.getJsonBody()
        LOG.D2("POI: byFloor: " + Utils.stripJsValueStr(json))
        val checkRequirements = VALIDATE.checkRequirements(json, SCHEMA.fBuid, SCHEMA.fFloorNumber)
        if (checkRequirements != null) return checkRequirements
        val buid = (json \ SCHEMA.fBuid).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid buid."))
        val floorNum = (json \ SCHEMA.fFloorNumber).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid floor_number."))
        try {
          val storedSpace = pds.db.getFromKeyAsJson(SCHEMA.cSpaces, SCHEMA.fBuid, buid)
          if (storedSpace == null) return RESPONSE.NOT_FOUND("Space not found.")
          val pois = pds.db.poisByBuildingFloorAsJson(buid, floorNum)
          val res: JsValue = Json.obj(SCHEMA.cPOIS -> pois)
          try {
            RESPONSE.gzipJsonOk(res.toString)
          } catch {
            case _: IOException => return RESPONSE.OK(res, "Retrieved pois. floor: " + floorNum)
          }
        } catch {
          case e: DatasourceException => return RESPONSE.ERROR(e)
        }
      }

      Future { inner(request) }(blockingEc)
  }

  def bySpace(): Action[AnyContent] = Action.async {
    implicit request =>
      def inner(request: Request[AnyContent]): Result = {
        val anyReq = new OAuth2Request(request)
        if (!anyReq.assertJsonBody()) return RESPONSE.BAD(RESPONSE.ERROR_JSON_PARSE)
        val json = anyReq.getJsonBody()
        LOG.D2("POI: bySpace: " + Utils.stripJsValueStr(json))
        val checkRequirements = VALIDATE.checkRequirements(json, SCHEMA.fBuid)
        if (checkRequirements != null) return checkRequirements
        val buid = (json \ SCHEMA.fBuid).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid buid."))
        try {
          val storedSpace = pds.db.getFromKeyAsJson(SCHEMA.cSpaces, SCHEMA.fBuid, buid)
          if (storedSpace == null) return RESPONSE.NOT_FOUND("Space not found.")
          val pois = pds.db.poisByBuildingAsJson(buid)
          val res: JsValue = Json.obj(SCHEMA.cPOIS -> pois.asScala)
          try {
            RESPONSE.gzipJsonOk(res.toString)
          } catch {
            case _: IOException => return RESPONSE.OK(res, "Retrieved space pois.")
          }
        } catch {
          case e: DatasourceException => return RESPONSE.ERROR(e)
        }
      }

      Future { inner(request) }(blockingEc)
  }

  /**
   * Retrieve all the pois of a cuid combination.
   * Available searchs in english and greeklish.
   *
   * @return
   */
  def search: Action[AnyContent] = Action.async {
    implicit request =>
      def inner(request: Request[AnyContent]): Result = {
        LOG.D2("POI: search")
        val anyReq = new OAuth2Request(request)
        if (!anyReq.assertJsonBody())
          return RESPONSE.BAD(RESPONSE.ERROR_JSON_PARSE)
        val json = anyReq.getJsonBody()
        LOG.D3("json = " + json)
        // Query-string overrides JSON body; `letters` is required.
        val cuid = request.getQueryString(SCHEMA.fConCuid)
          .orElse((json \ SCHEMA.fConCuid).asOpt[String]).getOrElse("")
        val letters = request.getQueryString("letters")
          .orElse((json \ "letters").asOpt[String]).orNull
        if (letters == null) return RESPONSE.MISSING_FIELDS(java.util.Collections.singletonList("letters"))
        val trimmedLetters = letters.trim
        if (trimmedLetters.length > MAX_SEARCH_QUERY_LENGTH ||
          trimmedLetters.split("\\s+").count(_.nonEmpty) > MAX_SEARCH_WORDS)
          return RESPONSE.BAD("Search query is too long.")
        val buid = request.getQueryString(SCHEMA.fBuid)
          .orElse((json \ SCHEMA.fBuid).asOpt[String]).getOrElse("")
        val greeklish = request.getQueryString(SCHEMA.fGreeklish)
          .orElse((json \ SCHEMA.fGreeklish).asOpt[String]).getOrElse("")
        try {
          val cacheKey = cuid + "|" + buid + "|" + greeklish + "|" + letters
          val result = SearchCache.get(cacheKey).getOrElse {
            val fresh =
              if (cuid.compareTo("") == 0)
                pds.db.poisByBuildingAsJson3(buid, letters)
              else if (greeklish.compareTo("true") == 0)
                pds.db.poisByBuildingAsJson2GR(cuid, letters)
              else
                pds.db.poisByBuildingAsJson2(cuid, letters)
            SearchCache.put(cacheKey, fresh)
            fresh
          }
          val res: JsValue = Json.obj(SCHEMA.cPOIS -> result)
          try
            RESPONSE.gzipJsonOk(res.toString)
          catch {
            case ioe: IOException =>
              return RESPONSE.OK(res, "Retrieved space pois.")
          }
        } catch {
          case e: DatasourceException =>
            return RESPONSE.ERROR(e)
        }
      }

      Future { inner(request) }(blockingEc)
  }

  /**
   * Retrieve all the pois of a building/floor combination.
   *
   * @return
   */
  def byConnectors: Action[AnyContent] = Action {
    implicit request =>
      def inner(request: Request[AnyContent]): Result = {
        val anyReq = new OAuth2Request(request)
        if (!anyReq.assertJsonBody())
          return RESPONSE.BAD(RESPONSE.ERROR_JSON_PARSE)
        val json = anyReq.getJsonBody()
        LOG.I("POI: byConnectors" + Utils.stripJsValueStr(json))
        val requiredMissing = JsonUtils.hasProperties(json, SCHEMA.fBuid)
        if (!requiredMissing.isEmpty)
          return RESPONSE.MISSING_FIELDS(requiredMissing)
        if (String(json, SCHEMA.fBuid) == null)
          return RESPONSE.BAD("buid field must be String.")
        val buid = (json \ SCHEMA.fBuid).as[String]
        try {
          val pois = pds.db.poisByBuildingIDAsJson(buid)
          val res: JsValue = Json.obj(SCHEMA.cPOIS -> pois)
          try
            RESPONSE.gzipJsonOk(res.toString)
          catch {
            case ioe: IOException =>
              return RESPONSE.OK(res, "Retrieved all POIs from space: " + buid)
          }
        } catch {
          case e: DatasourceException =>
            return RESPONSE.ERROR(e)
        }
      }

      inner(request)
  }

}
