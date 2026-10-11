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
import java.util
import javax.inject.{Inject, Singleton}
import scala.jdk.CollectionConverters.CollectionHasAsScala
@Singleton
class MapCampusController @Inject()(cc: ControllerComponents,
                                   pds: ProxyDataSource,
                                   user: helper.User)
  extends AbstractController(cc) {

  /**
   * Returns a campus.
   */
  def get: Action[AnyContent] = Action {
    implicit request =>
      def inner(request: Request[AnyContent]): Result = {
        val anyReq = new OAuth2Request(request)
        if (!anyReq.assertJsonBody()) return RESPONSE.BAD(RESPONSE.ERROR_JSON_PARSE)
        val json = anyReq.getJsonBody()
        LOG.D2("Campus: get")
        val checkRequirements = VALIDATE.checkRequirements(json, SCHEMA.fCampusCuid)
        if (checkRequirements != null) return checkRequirements
        val cuid = (json \ SCHEMA.fCampusCuid).as[String]
        try {
          val campus = try {
            pds.db.getBuildingSet(cuid)
          } catch {
            case _: Exception => return RESPONSE.ERROR_INTERNAL("Could not retrieve campus.")
          }
          if (campus.isEmpty) {
            return RESPONSE.NOT_FOUND("Campus not found!")
          } else if (campus.size > 1) {
            return RESPONSE.ERROR_INTERNAL("Duplicate campus.")
          }

          val buids = new util.ArrayList[String]
          for (c <- campus) {
            val cBuildings = (c \ SCHEMA.fBuids).asOpt[List[String]].getOrElse(Nil)
            for (cb <- cBuildings) {
              buids.add(cb)
            }
          }

          val spaces = new util.ArrayList[JsValue]
          for (b <- buids.asScala) {
            val space = try {
              pds.db.getFromKey(SCHEMA.cSpaces, SCHEMA.fBuid, b)
            } catch {
              case _: Exception => null
            }
            if (space != null) // some spaces are deleted but still exist in buids[] of a campus
              space.asOpt[JsObject].foreach { s =>
                spaces.add(s - SCHEMA.fId - SCHEMA.fSchema - SCHEMA.fCoOwners - SCHEMA.fGeometry - SCHEMA.fType - SCHEMA.fOwnerId)
              }
          }

          val res = campus.head.asOpt[JsObject].getOrElse(return RESPONSE.ERROR_INTERNAL("Invalid campus data.")) -
            SCHEMA.fBuids - SCHEMA.fOwnerId - SCHEMA.fId - SCHEMA.fSchema - SCHEMA.fCampusCuid - SCHEMA.fDescription +
            (SCHEMA.cSpaces -> Json.toJson(spaces.asScala))
          try
            RESPONSE.gzipJsonOk(res.toString)
          catch {
            case ioe: IOException => RESPONSE.OK(res, "Successfully retrieved spaceSets")
          }
        } catch {
          case e: DatasourceException => RESPONSE.ERROR(e)
        }
      }

      inner(request)
  }

  /**
   * Adds a new Space set to the database
   *
   * @return the newly created Space ID is included in the response if success
   */
  def add: Action[AnyContent] = Action {
    implicit request =>
      def inner(request: Request[AnyContent]): Result = {
        val anyReq = new OAuth2Request(request)
        val apiKey = anyReq.getAccessToken()
        if (apiKey == null) return anyReq.NO_ACCESS_TOKEN()
        if (!anyReq.assertJsonBody())
          return RESPONSE.BAD(RESPONSE.ERROR_JSON_PARSE)
        var json = anyReq.getJsonBody()
        LOG.D2("Campus: add")
        val checkRequirements = VALIDATE.checkRequirements(json, SCHEMA.fDescription, SCHEMA.fName, SCHEMA.fBuids, SCHEMA.fGreeklish)
        if (checkRequirements != null) return checkRequirements
        var owner_id = user.authorize(apiKey)
        if (owner_id == null) return RESPONSE.UNAUTHORIZED_USER
        json = json.asOpt[JsObject].getOrElse(return RESPONSE.BAD("Body must be a JSON object.")) +
          (SCHEMA.fOwnerId -> JsString(owner_id)) - SCHEMA.fAccessToken
        try {
          // cuid is optional: omitted means a fresh id is minted.
          val requestedCuid = (json \ SCHEMA.fCampusCuid).asOpt[String].map(_.trim).filter(_.nonEmpty)
          if (requestedCuid.exists(c => pds.db.BuildingSetsCuids(c)))
            return RESPONSE.BAD("Campus already exists.")
          val buids = (json \ SCHEMA.fBuids).asOpt[List[String]]
            .getOrElse(return RESPONSE.BAD("Invalid buids."))
          for (b <- buids) {
            val space = pds.db.getFromKeyAsJson(SCHEMA.cSpaces, SCHEMA.fBuid, b)
            if (space == null) return RESPONSE.BAD("Unknown buid in buids.")
            // Membership is ownership: without this, anyone grafts buildings
            // they do not own into their own campus roster.
            if (!user.canAccessSpace(space, owner_id))
              return RESPONSE.FORBIDDEN("Cannot add a space you do not own.")
          }
          var spaceSet: Campus = null
          try {
            spaceSet = new Campus(json)
          } catch {
            case _: Exception => return RESPONSE.BAD("Invalid campus payload.")
          }
            if (!pds.db.addJson(SCHEMA.cCampuses, spaceSet.addBuids()))
              return RESPONSE.BAD_CANNOT_ADD_SPACE
            val res: JsValue = Json.obj(SCHEMA.fCampusCuid -> spaceSet.getId())
            return RESPONSE.OK(res, "Successfully added Space Set.")
        } catch {
          case e: DatasourceException =>
            return RESPONSE.ERROR(e)
        }
      }

      inner(request)
  }

  /**
   * Update the Space information. Space to update is specified by buid
   *
   * @return
   */
  def update: Action[AnyContent] = Action {
    implicit request =>
      def inner(request: Request[AnyContent]): Result = {
        val anyReq = new OAuth2Request(request)
        val apiKey = anyReq.getAccessToken()
        if (apiKey == null) return anyReq.NO_ACCESS_TOKEN()
        if (!anyReq.assertJsonBody())
          return RESPONSE.BAD(RESPONSE.ERROR_JSON_PARSE)
        var json = anyReq.getJsonBody()
        LOG.D2("Campus: update: " + Utils.stripJsValueStr(json))
        val checkRequirements = VALIDATE.checkRequirements(json, SCHEMA.fCampusCuid)
        if (checkRequirements != null) return checkRequirements
        val owner_id = user.authorize(apiKey)
        if (owner_id == null) return RESPONSE.UNAUTHORIZED_USER
        json = json.asOpt[JsObject].getOrElse(return RESPONSE.BAD("Body must be a JSON object.")) +
          (SCHEMA.fOwnerId -> Json.toJson(owner_id))
        val cuid = (json \ SCHEMA.fCampusCuid).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid cuid."))
        try {
          var storedCampus = try {
            pds.db.getFromKeyAsJson(SCHEMA.cCampuses, SCHEMA.fCampusCuid, cuid)
          } catch {
            case _: Exception => return RESPONSE.ERROR_INTERNAL("Could not retrieve campus.")
          }
          if (storedCampus == null)
            return RESPONSE.NOT_FOUND("Campus not found.")
          if (!isCampusOwner(storedCampus, owner_id))
            return RESPONSE.FORBIDDEN("Unauthorized")
          // check for values to update
          if ((json \ SCHEMA.fName).toOption.isDefined) {
            val temp = (json \ SCHEMA.fName).asOpt[String].getOrElse(return RESPONSE.BAD("Invalid name."))
            if (temp != "-" && temp != "") {
              storedCampus = storedCampus.as[JsObject] + (SCHEMA.fName -> JsString(temp))
            } else {
              storedCampus = storedCampus.as[JsObject] - SCHEMA.fName
            }
          }
          if ((json \ SCHEMA.fDescription).toOption.isDefined) {
            val temp = (json \ SCHEMA.fDescription).asOpt[String].getOrElse(return RESPONSE.BAD("Invalid description."))
            if (temp != "-" && temp != "") {
              storedCampus = storedCampus.as[JsObject] + (SCHEMA.fDescription, JsString(temp))
            } else
              storedCampus = storedCampus.as[JsObject] - SCHEMA.fDescription
          }
          (json \ "cuidnew").asOpt[String].map(_.trim).filter(t => t.nonEmpty && t != "-").foreach { nc =>
            if (nc != cuid && pds.db.BuildingSetsCuids(nc)) return RESPONSE.BAD("Campus already exists.")
            storedCampus = storedCampus.as[JsObject] + (SCHEMA.fCampusCuid -> JsString(nc))
          }
          if ((json \ SCHEMA.fGreeklish).toOption.isDefined) {
            val gval: String = (json \ SCHEMA.fGreeklish).asOpt[Boolean].map(_.toString)
              .orElse((json \ SCHEMA.fGreeklish).asOpt[String])
              .getOrElse(return RESPONSE.BAD("Invalid greeklish flag."))
            storedCampus = storedCampus.as[JsObject] + (SCHEMA.fGreeklish -> JsString(gval))
          }
          if ((json \ SCHEMA.fBuids).toOption.isDefined) {
            LOG.D2(json.toString())
            val buids = (json \ SCHEMA.fBuids).asOpt[List[String]]
              .getOrElse(return RESPONSE.BAD("Invalid buids."))
            for (b <- buids) {
              val space = pds.db.getFromKeyAsJson(SCHEMA.cSpaces, SCHEMA.fBuid, b)
              if (space == null) return RESPONSE.BAD("Unknown buid in buids.")
              if (!user.canAccessSpace(space, owner_id))
                return RESPONSE.FORBIDDEN("Cannot add a space you do not own.")
            }
            storedCampus = storedCampus.as[JsObject] + (SCHEMA.fBuids -> Json.toJson(buids))
          }
          val campus = new Campus(storedCampus)
          // Replace by the ORIGINAL cuid: a rename must not orphan the row.
          if (!pds.db.replaceJsonDocument(SCHEMA.cCampuses, SCHEMA.fCampusCuid, cuid, campus.toGeoJsonStr()))
            return RESPONSE.BAD("Campus could not be updated.")
          return RESPONSE.OK("Successfully updated campus.")
        } catch {
          case e: DatasourceException =>
            return RESPONSE.ERROR(e)
        }
      }

      inner(request)
  }

  def byOwner: Action[AnyContent] = Action {
    implicit request =>
      def inner(request: Request[AnyContent]): Result = {
        val anyReq = new OAuth2Request(request)
        val apiKey = anyReq.getAccessToken()
        if (apiKey == null) return anyReq.NO_ACCESS_TOKEN()
        // byOwner needs no parameters: accept empty bodies too.
        var json = if (anyReq.assertJsonBody()) anyReq.getJsonBody() else Json.obj()
        LOG.D2("Campus: byOwner")
        val owner_id = user.authorize(apiKey)
        if (owner_id == null) return RESPONSE.UNAUTHORIZED_USER
        json = json.asOpt[JsObject].getOrElse(return RESPONSE.BAD("Body must be a JSON object.")) +
          (SCHEMA.fOwnerId -> Json.toJson(owner_id))
        try {
          val buildingsets = pds.db.getAllBuildingsetsByOwner(owner_id)
          val res: JsValue = Json.obj("buildingsets" -> buildingsets)
          try
            RESPONSE.gzipJsonOk(res.toString)
          catch {
            case ioe: IOException =>
              return RESPONSE.OK(res, "Successfully retrieved all buildingsets.")
          }
        } catch {
          case e: DatasourceException =>
            return RESPONSE.ERROR(e)
        }
      }

      inner(request)
  }

  /**
   * Delete the campus specified by cuid.
   *
   * @return
   */
  def delete: Action[AnyContent] = Action {
    implicit request =>
      def inner(request: Request[AnyContent]): Result = {
        val anyReq = new OAuth2Request(request)
        val apiKey = anyReq.getAccessToken()
        if (apiKey == null) return anyReq.NO_ACCESS_TOKEN()
        if (!anyReq.assertJsonBody())
          return RESPONSE.BAD(RESPONSE.ERROR_JSON_PARSE)
        var json = anyReq.getJsonBody()
        LOG.D2("Campus: delete: " + Utils.stripJsValueStr(json))
        val checkRequirements = VALIDATE.checkRequirements(json, SCHEMA.fCampusCuid)
        if (checkRequirements != null) return checkRequirements
        val owner_id = user.authorize(apiKey)
        if (owner_id == null) return RESPONSE.UNAUTHORIZED_USER
        json = json.asOpt[JsObject].getOrElse(return RESPONSE.BAD("Body must be a JSON object.")) +
          (SCHEMA.fOwnerId -> Json.toJson(owner_id))
        val cuid = (json \ SCHEMA.fCampusCuid).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid cuid."))
        try {
          val storedCampus = pds.db.getFromKeyAsJson(SCHEMA.cCampuses, SCHEMA.fCampusCuid, cuid)
          if (storedCampus == null)
            return RESPONSE.NOT_FOUND("Campus not found.")
          if (!isCampusOwner(storedCampus, owner_id))
            return RESPONSE.FORBIDDEN("Unauthorized")
          if (!pds.db.deleteFromKey(SCHEMA.cCampuses, SCHEMA.fCampusCuid, cuid))
            return RESPONSE.ERROR_INTERNAL("Failed to delete Campus")
        } catch {
          case e: DatasourceException =>
            return RESPONSE.ERROR(e)
        }

        RESPONSE.OK("Deleted campus. Member spaces are retained.")
      }

      inner(request)
  }

  private def isCampusOwner(campus: JsValue, userId: String): Boolean = {
    if (userId == null) return false
    if (user.isAdminOrModerator(userId)) return true
    if (campus != null) {
      return (campus \ SCHEMA.fOwnerId).asOpt[String].exists(_ == userId)
    }
    false
  }

}