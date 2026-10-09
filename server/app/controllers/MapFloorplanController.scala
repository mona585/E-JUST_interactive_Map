package controllers

import controllers.FloorplanSettings.MIN_ZOOM_UPLOAD
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

object FloorplanSettings {
  /** It no longer affects upload quality (fixed JS), but it might affect accuracy. */
  var MIN_ZOOM_UPLOAD=18
}

@Singleton
class MapFloorplanController @Inject()(cc: ControllerComponents,
                                       tilerHelper: AnyPlaceTilerHelper,
                                       pds: ProxyDataSource,
                                       fu: FileUtils,
                                       user: helper.User)
  extends AbstractController(cc) {
  implicit val ec: scala.concurrent.ExecutionContext = scala.concurrent.ExecutionContext.global

  def serveFloorPlanBinary(buid: String, floorNum: String): Action[AnyContent] = Action {
    implicit request =>

      def inner(request: Request[AnyContent]): Result = {
        val anyReq = new OAuth2Request(request)
        if (!anyReq.assertJsonBody()) return RESPONSE.BAD(RESPONSE.ERROR_JSON_PARSE)
        val json = anyReq.getJsonBody()
        LOG.D2("serveFloorPlanBinary: " + Utils.stripJsValueStr(json))
        if (!Utils.isSafePathSegment(buid) || !Utils.isSafePathSegment(floorNum))
          return RESPONSE.BAD("Invalid building or floor identifier.")
        val filePath = tilerHelper.getFloorPlanFor(buid, floorNum)
        LOG.D2("requested: " + filePath)
        if (!Utils.isWithinRoot(tilerHelper.getRootFloorPlansDir(), filePath))
          return RESPONSE.BAD("Invalid building or floor identifier.")
        try {
          val file = new File(filePath)
          if (!file.exists()) return RESPONSE.BAD_CANNOT_RETRIEVE_FLOORPLAN(floorNum)
          if (!file.canRead) return RESPONSE.BAD_CANNOT_READ_FLOORPLAN(floorNum)
          Ok.sendFile(file)
        } catch {
          case _: FileNotFoundException => return RESPONSE.ERROR_INTERNAL("Could not read floorplan.")
        }
      }

      inner(request)
  }

  def getTilesZip(buid: String, floorNum: String): Action[AnyContent] = Action {
    implicit request =>

      def inner(request: Request[AnyContent]): Result = {
        val anyReq = new OAuth2Request(request)
        if (!anyReq.assertJsonBody()) return RESPONSE.BAD(RESPONSE.ERROR_JSON_PARSE)
        var json = anyReq.getJsonBody()
        LOG.D2("FloorPlan: getTilesZip: " + Utils.stripJsValueStr(json))
        if (!Floor.checkFloorNumberFormat(floorNum)) return RESPONSE.BAD("Floor number cannot contain whitespace.")
        if (!Utils.isSafePathSegment(buid) || !Utils.isSafePathSegment(floorNum))
          return RESPONSE.BAD("Invalid building or floor identifier.")
        val filePath = tilerHelper.getFloorTilesZipFor(buid, floorNum)
        LOG.D3("requested: " + filePath)
        if (!Utils.isWithinRoot(tilerHelper.getRootFloorPlansDir(), filePath))
          return RESPONSE.BAD("Invalid building or floor identifier.")
        try {
          val file = new File(filePath)
          if (!file.exists()) return RESPONSE.BAD_CANNOT_RETRIEVE_FLOORPLAN(floorNum)
          if (!file.canRead) return RESPONSE.BAD_CANNOT_READ_FLOORPLAN(floorNum)
          Ok.sendFile(file)
        } catch {
          case e: FileNotFoundException => return RESPONSE.ERROR_INTERNAL("Could not read floorplan.")
        }
      }

      inner(request)
  }

  def getZipLink(buid: String, floorNum: String): Action[AnyContent] = Action {
    implicit request =>

      def inner(request: Request[AnyContent]): Result = {
        val anyReq = new OAuth2Request(request)
        if (!anyReq.assertJsonBody()) return RESPONSE.BAD(RESPONSE.ERROR_JSON_PARSE)
        var json = anyReq.getJsonBody()
        LOG.D2("Floorplan:: getZipLink: " + Utils.stripJsValueStr(json))
        if (!Floor.checkFloorNumberFormat(floorNum)) return RESPONSE.BAD("Floor number cannot contain whitespace.")
        if (!Utils.isSafePathSegment(buid) || !Utils.isSafePathSegment(floorNum))
          return RESPONSE.BAD("Invalid building or floor identifier.")
        val filePath = tilerHelper.getFloorTilesZipFor(buid, floorNum)
        LOG.D3("requested: " + filePath)
        if (!Utils.isWithinRoot(tilerHelper.getRootFloorPlansDir(), filePath))
          return RESPONSE.BAD("Invalid building or floor identifier.")
        val file = new File(filePath)
        if (!file.exists()) return RESPONSE.BAD_CANNOT_RETRIEVE_FLOORPLAN(floorNum)
        if (!file.canRead) return RESPONSE.BAD_CANNOT_READ_FLOORPLAN(floorNum)
        val res: JsValue = Json.obj("tiles_archive" -> tilerHelper.getFloorTilesZipLinkFor(buid, floorNum))
        return RESPONSE.OK(res, "Successfully fetched link for the tiles archive.")
      }

      inner(request)
  }

  def getStaticTiles(buid: String, floorNum: String, path: String): Action[AnyContent] = Action {
    def inner(): Result = {
      if (path == null || buid == null || floorNum == null ||
        path.trim().isEmpty ||
        buid.trim().isEmpty ||
        floorNum.trim().isEmpty) return NotFound(<h1>Page not found</h1>)
      if (!Utils.isSafePathSegment(buid) || !Utils.isSafePathSegment(floorNum) ||
        !Utils.isSafeRelativePath(path)) return NotFound(<h1>Page not found</h1>)
      var filePath: String = null
      filePath = if (path == tilerHelper.FLOOR_TILES_ZIP_NAME) tilerHelper.getFloorTilesZipFor(buid,
        floorNum) else tilerHelper.getFloorTilesDirFor(buid, floorNum) +
        path
      try {
        val file = new File(filePath)
        if (!Utils.isWithinRoot(tilerHelper.getRootFloorPlansDir(), file.getPath))
          return NotFound(<h1>Page not found</h1>)
        //send ok message to tiler
        if (!file.exists() || !file.canRead) return RESPONSE.OK("File requested not found")
        Ok.sendFile(file)
      } catch {
        case _: FileNotFoundException => return RESPONSE.BAD_CANNOT_READ_FLOORPLAN(floorNum)
      }
    }

    inner()
  }

  def getBase64(buid: String, floorNum: String): Action[AnyContent] = Action {
    implicit request =>
      def inner(request: Request[AnyContent]): Result = {
        val anyReq = new OAuth2Request(request)
        if (!anyReq.assertJsonBody()) return RESPONSE.BAD(RESPONSE.ERROR_JSON_PARSE)
        var json = anyReq.getJsonBody()
        LOG.D2("Floorplan: getBase64: " + Utils.stripJsValueStr(json))
        if (!Utils.isSafePathSegment(buid) || !Utils.isSafePathSegment(floorNum))
          return RESPONSE.BAD("Invalid building or floor identifier.")
        val filePath = tilerHelper.getFloorPlanFor(buid, floorNum)
        LOG.D3("Floorplan: getBase64: requested: " + filePath)
        if (!Utils.isWithinRoot(tilerHelper.getRootFloorPlansDir(), filePath))
          return RESPONSE.BAD("Invalid building or floor identifier.")
        val file = new File(filePath)
        try {
          if (!file.exists()) return RESPONSE.BAD_CANNOT_RETRIEVE_FLOORPLAN(floorNum)
          if (!file.canRead) return RESPONSE.BAD_CANNOT_READ_FLOORPLAN(floorNum)

          try {
            val s = Utils.encodeFileToBase64Binary(fu, filePath)
            try {
              RESPONSE.gzipOk(s)
            } catch {
              case ioe: IOException => Ok(s)
            }
          } catch {
            case e: IOException => return RESPONSE.BAD("Requested floorplan cannot be encoded in base64 properly: " +
              floorNum)
          }
        } catch {
          case e: Exception => return RESPONSE.ERROR_INTERNAL("Unknown server error during floorplan delivery.")
        }
      }

      inner(request)
  }

  /**
   * Returns the floorplan in base64 form. Used by the Anyplace websites
   *
   * @param buid
   * @param floorNum
   * @return
   */
  def getAllBase64(buid: String, requestedFloors: String): Action[AnyContent] = Action {
    implicit request =>
      def inner(request: Request[AnyContent]): Result = {
        val anyReq = new OAuth2Request(request)
        if (!anyReq.assertJsonBody())
          return RESPONSE.BAD(RESPONSE.ERROR_JSON_PARSE)
        val json = anyReq.getJsonBody()
        LOG.D2("Floorplan: getAllBase64: " + Utils.stripJsValueStr(json) + " " + requestedFloors)
        if (!Utils.isSafePathSegment(buid)) return RESPONSE.BAD("Invalid building identifier.")
        val floors = requestedFloors.split(" ")
        if (!floors.forall(Utils.isSafePathSegment)) return RESPONSE.BAD("Invalid floor identifier.")
        val all_floors = new util.ArrayList[String]
        var z = 0
        while (z < floors.length) {
          val filePath = tilerHelper.getFloorPlanFor(buid, floors(z))
          LOG.D3("Floorplan: getAllBase64: requested: " + filePath)
          if (!Utils.isWithinRoot(tilerHelper.getRootFloorPlansDir(), filePath))
            return RESPONSE.BAD("Invalid building or floor identifier.")
          val file = new File(filePath)
          try
            if (!file.exists || !file.canRead) { all_floors.add("") }
            else try {
              val s = Utils.encodeFileToBase64Binary(fu, filePath)
              all_floors.add(s)
            } catch {
              case _: IOException =>
                return RESPONSE.BAD("Cannot encode floorplan: " + floors(z))
            }
          catch {
            case e: Exception =>
              return RESPONSE.ERROR_INTERNAL("Error while getting floorplans: " + requestedFloors +" : "
              + e.getMessage)
          }
          z += 1
        }
        val res: JsValue = Json.obj("all_floors" -> all_floors.asScala)
        try {
          RESPONSE.gzipJsonOk(res.toString)
        } catch {
          case _: IOException =>
            RESPONSE.OK(res, "Floors retrieved.")
        }
      }

      inner(request)
  }

  @deprecated("NotInUse")
  def upload(): Action[AnyContent] = Action {
    implicit request =>

      def inner(request: Request[AnyContent]): Result = {
        val anyReq = new OAuth2Request(request)
        val apiKey = anyReq.getAccessToken()
        if (apiKey == null) return anyReq.NO_ACCESS_TOKEN()
        val body = anyReq.getMultipartFormData()
        if (body == null) return RESPONSE.BAD("Invalid request type - Not Multipart.")
        val floorplan = body.file("floorplan").orNull
        if (floorplan == null) return RESPONSE.BAD("Cannot find the floorplan file in your request.")
        val urlenc = body.asFormUrlEncoded
        val json_str = urlenc("").head
        if (json_str == null) return RESPONSE.BAD("Cannot find json in the request.")
        var json: JsValue = null
        try {
          json = Json.parse(json_str)
        } catch {
          case e: IOException => return RESPONSE.BAD_PARSE_JSON
        }
        LOG.I("Floorplan Request[json]: " + json.toString)
        LOG.I("Floorplan Request[floorplan]: " + floorplan.filename)
        val requiredMissing = JsonUtils.hasProperties(json, SCHEMA.fBuid, SCHEMA.fFloorNumber, SCHEMA.fLatBottomLeft,
          SCHEMA.fLonBottomLeft, SCHEMA.fLatTopRight, SCHEMA.fLonTopRight)
        if (!requiredMissing.isEmpty) return RESPONSE.MISSING_FIELDS(requiredMissing)
        val buid = (json \ SCHEMA.fBuid).as[String]
        if (!Utils.isSafePathSegment(buid)) return RESPONSE.BAD("Invalid building identifier.")
        val owner_id = user.authorize(apiKey)
        if (owner_id == null) return RESPONSE.UNAUTHORIZED_USER
        try {
          val storedSpace = pds.db.getFromKeyAsJson(SCHEMA.cSpaces, SCHEMA.fBuid, buid)
          if (storedSpace == null) return RESPONSE.BAD_CANNOT_RETRIEVE_SPACE
          if (!user.canAccessSpace(storedSpace, owner_id)) return RESPONSE.UNAUTHORIZED_USER
        } catch {
          case _: DatasourceException => return RESPONSE.ERROR_INTERNAL("Error while reading from backend.")
        }
        val floorNum = (json \ SCHEMA.fFloorNumber).as[String]
        if (!Utils.isSafePathSegment(floorNum)) return RESPONSE.BAD("Invalid floor identifier.")
        val bottom_left_lat = (json \ SCHEMA.fLatBottomLeft).as[String]
        val bottom_left_lng = (json \ SCHEMA.fLonBottomLeft).as[String]
        val top_right_lat = (json \ SCHEMA.fLatTopRight).as[String]
        val top_right_lng = (json \ SCHEMA.fLonTopRight).as[String]
        val fuid = Floor.getId(buid, floorNum)
        try {
          var storedFloor = pds.db.getFromKeyAsJson(SCHEMA.cFloorplans, SCHEMA.fFuid, fuid)
          if (storedFloor == null) return RESPONSE.BAD_CANNOT_RETRIEVE_FLOOR
          storedFloor = storedFloor.as[JsObject] + (SCHEMA.fLatBottomLeft -> JsString(bottom_left_lat))
          storedFloor = storedFloor.as[JsObject] + (SCHEMA.fLonBottomLeft -> JsString(bottom_left_lng))
          storedFloor = storedFloor.as[JsObject] + (SCHEMA.fLatTopRight -> JsString(top_right_lat))
          storedFloor = storedFloor.as[JsObject] + (SCHEMA.fLonTopRight -> JsString(top_right_lng))
          if (!pds.db.replaceJsonDocument(SCHEMA.cFloorplans, SCHEMA.fFuid, fuid, storedFloor.toString))
            return RESPONSE.BAD("floorplan could not be updated in the database.")
        } catch {
          case _: DatasourceException => return RESPONSE.ERROR_INTERNAL("Error while reading from our backend service.")
        }
        var floor_file: File = null
        try {
          floor_file = tilerHelper.storeFloorPlanToServer(buid, floorNum, floorplan.ref.file)
        } catch {
          case e: AnyPlaceException => return RESPONSE.BAD("Cannot save floorplan on the server.")
        }
        val top_left_lat = top_right_lat
        val top_left_lng = bottom_left_lng
        try {
          tilerHelper.tileImage(floor_file, top_left_lat, top_left_lng)
        } catch {
          case e: AnyPlaceException => return RESPONSE.BAD("Could not create floorplan tiles on the server.")
        }
        LOG.I("Successfully tiled: " + floor_file.toString)
        return RESPONSE.OK("Successfully updated floorplan.")
      }

      inner(request)
  }

  /**
   * After a floor was added, this endpoints:
   *    1. uploads a floorplan (filesystem)
   *    2. updates the floor with the coordinates of the floorplan (db)
   */
  def uploadWithZoom(): Action[AnyContent] = Action {
    implicit request =>

      def inner(request: Request[AnyContent]): Result = {
        LOG.D2("Floorplan: uploadWithZoom")
        val anyReq = new OAuth2Request(request)
        val apiKey = anyReq.getAccessToken()
        if (apiKey == null) return anyReq.NO_ACCESS_TOKEN()
        val body = anyReq.getMultipartFormData()
        if (body == null) return RESPONSE.BAD("Invalid request type - Not Multipart.")
        val floorplan = body.file("floorplan").orNull
        if (floorplan == null) return RESPONSE.BAD("Cannot find the floorplan file in your request.")
        val urlenc = body.asFormUrlEncoded
        val json_str = urlenc("json").head
        if (json_str == null) return RESPONSE.BAD("Cannot find json in the request.")
        var json: JsValue = null
        try {
          json = Json.parse(json_str)
        } catch {
          case _: IOException => return RESPONSE.BAD_PARSE_JSON
        }
        val checkRequirements = VALIDATE.checkRequirements(json, SCHEMA.fBuid, SCHEMA.fFloorNumber, SCHEMA.fLatBottomLeft,
          SCHEMA.fLonBottomLeft, SCHEMA.fLatTopRight, SCHEMA.fLonTopRight, SCHEMA.fZoom)
        if (checkRequirements != null) return checkRequirements
        val buid = (json \ SCHEMA.fBuid).as[String]
        val owner_id = user.authorize(apiKey)
        if (owner_id == null) return RESPONSE.UNAUTHORIZED_USER
        try {
          val storedSpace = pds.db.getFromKeyAsJson(SCHEMA.cSpaces, SCHEMA.fBuid, buid)
          if (storedSpace == null) return RESPONSE.BAD_CANNOT_RETRIEVE_SPACE
          if (!user.canAccessSpace(storedSpace, owner_id)) return RESPONSE.UNAUTHORIZED_USER
        } catch {
          case _: DatasourceException => return RESPONSE.ERROR_INTERNAL("Error while reading from backend.")
        }
        val zoom = (json \ SCHEMA.fZoom).as[String]
        if (zoom.toInt < MIN_ZOOM_UPLOAD) return RESPONSE.BAD_FLOORPLAN_ZOOM_LEVEL(zoom)

        val floorNum = (json \ SCHEMA.fFloorNumber).as[String]
        if (!Utils.isSafePathSegment(floorNum)) return RESPONSE.BAD("Invalid floor identifier.")
        val bottom_left_lat = (json \ SCHEMA.fLatBottomLeft).as[String]
        val bottom_left_lng = (json \ SCHEMA.fLonBottomLeft).as[String]
        val top_right_lat = (json \ SCHEMA.fLatTopRight).as[String]
        val top_right_lng = (json \ SCHEMA.fLonTopRight).as[String]
        val fuid = Floor.getId(buid, floorNum)
        try {
          var storedFloor = pds.db.getFromKeyAsJson(SCHEMA.cFloorplans, SCHEMA.fFuid, fuid)
          if (storedFloor == null) return RESPONSE.BAD_CANNOT_RETRIEVE_FLOOR
          storedFloor = storedFloor.as[JsObject] + (SCHEMA.fZoom -> JsString(zoom))
          storedFloor = storedFloor.as[JsObject] + (SCHEMA.fLatBottomLeft -> JsString(bottom_left_lat))
          storedFloor = storedFloor.as[JsObject] + (SCHEMA.fLonBottomLeft -> JsString(bottom_left_lng))
          storedFloor = storedFloor.as[JsObject] + (SCHEMA.fLatTopRight -> JsString(top_right_lat))
          storedFloor = storedFloor.as[JsObject] + (SCHEMA.fLonTopRight -> JsString(top_right_lng))
          if (!pds.db.replaceJsonDocument(SCHEMA.cFloorplans, SCHEMA.fFuid, fuid, storedFloor.toString)) {
            return RESPONSE.BAD("Could not update floorplan.")
          }
        } catch {
          case _: DatasourceException => return RESPONSE.ERROR_INTERNAL("Error while reading from backend.")
        }
        var floor_file: File = null
        try {
          floor_file = tilerHelper.storeFloorPlanToServer(buid, floorNum, floorplan.ref.path.toFile)
        } catch {
          case _: AnyPlaceException => return RESPONSE.BAD("Cannot save floorplan.")
        }
        val top_left_lat = top_right_lat
        val top_left_lng = bottom_left_lng
        try {
          tilerHelper.tileImageWithZoom(floor_file, top_left_lat, top_left_lng, zoom)
        } catch {
          case _: AnyPlaceException => return RESPONSE.BAD("Cannot create floorplan tiles.")
        }
        LOG.I("Successfully tiled: " + floor_file.toString)

       RESPONSE.OK("Uploaded floorplan.")
      }

      inner(request)
  }

}
