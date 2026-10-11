package controllers

import datasources.{DatasourceException, ProxyDataSource, SCHEMA}
import models._
import models.oauth.OAuth2Request
import play.api.libs.json.Reads._
import play.api.libs.json._
import play.api.mvc._
import utils._
import utils.json.VALIDATE

import java.io._
import javax.inject.{Inject, Singleton}
import scala.jdk.CollectionConverters.CollectionHasAsScala
@Singleton
class MapFloorController @Inject()(cc: ControllerComponents,
                                   tilerHelper: AnyPlaceTilerHelper,
                                   pds: ProxyDataSource,
                                   user: helper.User)
  extends AbstractController(cc) {

  def add(): Action[AnyContent] = Action {
    implicit request =>
      def inner(request: Request[AnyContent]): Result = {
        val anyReq = new OAuth2Request(request)
        val apiKey = anyReq.getAccessToken()
        if (apiKey == null) return anyReq.NO_ACCESS_TOKEN()
        if (!anyReq.assertJsonBody()) return RESPONSE.BAD(RESPONSE.ERROR_JSON_PARSE)
        var json = anyReq.getJsonBody()
        LOG.D2("Floor: add: " + Utils.stripJsValueStr(json))
        val checkRequirements = VALIDATE.checkRequirements(json, SCHEMA.fIsPublished, SCHEMA.fBuid, SCHEMA.fFloorName,
          SCHEMA.fDescription, SCHEMA.fFloorNumber)
        if (checkRequirements != null) return checkRequirements
        val owner_id = user.authorize(apiKey)
        if (owner_id == null) return RESPONSE.UNAUTHORIZED_USER
        json = json.asOpt[JsObject].getOrElse(return RESPONSE.BAD("Body must be a JSON object.")) +
          (SCHEMA.fOwnerId -> Json.toJson(owner_id))
        val buid = (json \ SCHEMA.fBuid).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid buid."))
        try {
          val storedSpace = pds.db.getFromKeyAsJson(SCHEMA.cSpaces, SCHEMA.fBuid, buid)
          if (storedSpace == null) return RESPONSE.NOT_FOUND("Space not found.")
          if (!user.canAccessSpace(storedSpace, owner_id)) return RESPONSE.UNAUTHORIZED_USER
        } catch {
          case e: DatasourceException => return RESPONSE.ERROR(e)
        }
        val floorNum = (json \ SCHEMA.fFloorNumber).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid floor_number."))
        if (!Floor.checkFloorNumberFormat(floorNum)) return RESPONSE.BAD("Floor number cannot contain whitespace.")
        if (!Utils.isSafePathSegment(floorNum)) return RESPONSE.BAD("Invalid floor identifier.")
        try {
          // Duplicate guard: fuid is deterministic per building+floor.
          if (pds.db.getFromKeyAsJson(SCHEMA.cFloorplans, SCHEMA.fFuid, Floor.getId(buid, floorNum)) != null)
            return RESPONSE.BAD("Floor already exists.")
          json = json.as[JsObject] - SCHEMA.fAccessToken
          val floor = new Floor(json)
          if (!pds.db.addJson(SCHEMA.cFloorplans, Utils.stripJsValue(floor.toJson())))
            return RESPONSE.BAD_CANNOT_ADD_FLOOR

          return RESPONSE.OK("Successfully added floor " + floorNum + ".")
        } catch {
          case e: DatasourceException => return RESPONSE.ERROR(e)
        }
      }

      inner(request)
  }

  @deprecated("NotInUse")
  def floorUpdate(): Action[AnyContent] = Action {
    implicit request =>
      def inner(request: Request[AnyContent]): Result = {
        val anyReq = new OAuth2Request(request)
        val apiKey = anyReq.getAccessToken()
        if (apiKey == null) return anyReq.NO_ACCESS_TOKEN()
        if (!anyReq.assertJsonBody()) return RESPONSE.BAD(RESPONSE.ERROR_JSON_PARSE)
        var json = anyReq.getJsonBody()
        LOG.D2("Floor: update: " + Utils.stripJsValueStr(json))
        val requiredMissing = JsonUtils.hasProperties(json, SCHEMA.fBuid, SCHEMA.fFloorNumber)
        if (!requiredMissing.isEmpty) return RESPONSE.MISSING_FIELDS(requiredMissing)
        val owner_id = user.authorize(apiKey)
        if (owner_id == null) return RESPONSE.UNAUTHORIZED_USER
        json = json.asOpt[JsObject].getOrElse(return RESPONSE.BAD("Body must be a JSON object.")) +
          (SCHEMA.fOwnerId -> Json.toJson(owner_id))
        val buid = (json \ SCHEMA.fBuid).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid buid."))
        try {
          val storedSpace = pds.db.getFromKeyAsJson(SCHEMA.cSpaces, SCHEMA.fBuid, buid)
          if (storedSpace == null) return RESPONSE.NOT_FOUND("Space not found.")
          if (!user.canAccessSpace(storedSpace, owner_id)) return RESPONSE.UNAUTHORIZED_USER
        } catch {
          case e: DatasourceException => return RESPONSE.ERROR(e)
        }
        val floorNum = (json \ SCHEMA.fFloorNumber).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid floor_number."))
        if (!Floor.checkFloorNumberFormat(floorNum)) return RESPONSE.BAD("Floor number cannot contain whitespace.")
        try {
          val fuid = Floor.getId(buid, floorNum)
          var storedFloor = pds.db.getFromKeyAsJson(SCHEMA.cFloorplans, SCHEMA.fFuid, fuid)
          if (storedFloor == null) return RESPONSE.NOT_FOUND("Floor not found.")
          if ((json \ SCHEMA.fIsPublished).asOpt[String].exists(s => s == "true" || s == "false"))
            storedFloor = storedFloor.as[JsObject] + (SCHEMA.fIsPublished -> JsString((json \ SCHEMA.fIsPublished).as[String]))
          if ((json \ SCHEMA.fFloorName).asOpt[String].exists(_.trim.nonEmpty))
            storedFloor = storedFloor.as[JsObject] + (SCHEMA.fFloorName, JsString((json \ SCHEMA.fFloorName).as[String]))
          if ((json \ SCHEMA.fDescription).asOpt[String].isDefined)
            storedFloor = storedFloor.as[JsObject] + (SCHEMA.fDescription, JsString((json \ SCHEMA.fDescription).as[String]))
          val floor = new Floor(storedFloor)
          if (!pds.db.replaceJsonDocument(SCHEMA.cFloorplans, SCHEMA.fFuid, floor.getId(), floor.toJson().toString))
            return RESPONSE.BAD("Floor could not be updated.")
          return RESPONSE.OK("Successfully updated floor.")
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
        LOG.D2("Floor: delete: " + Utils.stripJsValueStr(json))
        val checkRequirements = VALIDATE.checkRequirements(json, SCHEMA.fBuid, SCHEMA.fFloorNumber)
        if (checkRequirements != null) return checkRequirements
        val owner_id = user.authorize(apiKey)
        if (owner_id == null) return RESPONSE.UNAUTHORIZED_USER
        json = json.asOpt[JsObject].getOrElse(return RESPONSE.BAD("Body must be a JSON object.")) +
          (SCHEMA.fOwnerId -> Json.toJson(owner_id))
        val buid = (json \ SCHEMA.fBuid).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid buid."))
        val floorNum = (json \ SCHEMA.fFloorNumber).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid floor_number."))
        if (!Floor.checkFloorNumberFormat(floorNum)) return RESPONSE.BAD("Floor number cannot contain whitespace.")
        if (!Utils.isSafePathSegment(floorNum)) return RESPONSE.BAD("Invalid floor identifier.")
        try {
          val storedSpace = pds.db.getFromKeyAsJson(SCHEMA.cSpaces, SCHEMA.fBuid, buid)
          if (storedSpace == null) return RESPONSE.NOT_FOUND("Space not found.")
          if (!user.canAccessSpace(storedSpace, owner_id)) return RESPONSE.UNAUTHORIZED_USER
        } catch {
          case e: DatasourceException => return RESPONSE.ERROR(e)
        }
        try {
          val deleted = pds.db.deleteAllByFloor(buid, floorNum)
          if (!deleted)
            return RESPONSE.BAD("Some items related to the floor could not be deleted.")
        } catch {
          case e: DatasourceException => return RESPONSE.ERROR(e)
        }
        val filePath = tilerHelper.getFloorPlanFor(buid, floorNum)
        try {
          val floorfile = new File(filePath)
          if (floorfile.exists()) HelperMethods.recDeleteDirFile(floorfile.getParentFile)
        } catch {
          case e: IOException => return RESPONSE.ERROR("While deleting floorplan." +
            "\nRelated data are deleted from the database.", e)
        }
        return RESPONSE.OK("Successfully deleted everything related to the floor.")
      }

      inner(request)
  }

  def all(): Action[AnyContent] = Action {
    implicit request =>
      def inner(request: Request[AnyContent]): Result = {
        val anyReq = new OAuth2Request(request)
        if (!anyReq.assertJsonBody()) return RESPONSE.BAD(RESPONSE.ERROR_JSON_PARSE)
        val json = anyReq.getJsonBody()
        LOG.D2("Floor: all: " + Utils.stripJsValueStr(json))
        val checkRequirements = VALIDATE.checkRequirements(json, SCHEMA.fBuid)
        if (checkRequirements != null) return checkRequirements
        val buid = (json \ SCHEMA.fBuid).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid buid."))
        try {
          val floors = pds.db.floorsByBuildingAsJson(buid)
          val res: JsValue = Json.obj("floors" -> floors.asScala)
          try {
            RESPONSE.gzipJsonOk(res.toString)
          } catch {
            case ioe: IOException => return RESPONSE.OK(res, "Successfully retrieved all floors.")
          }
        } catch {
          case e: DatasourceException => return RESPONSE.ERROR(e)
        }
      }

      inner(request)
  }

}
