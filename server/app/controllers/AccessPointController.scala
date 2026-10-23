package controllers

import datasources.{DatasourceException, ProxyDataSource, SCHEMA}

import models.oauth.OAuth2Request
import play.api.libs.json._
import play.api.mvc._
import play.api.Environment
import play.twirl.api.TwirlHelperImports.twirlJavaCollectionToScala
import utils.json.VALIDATE
import utils.{AccessPointIdsCache, LOG, RESPONSE, Utils}

import java.io.IOException
import java.util
import javax.inject.{Inject, Singleton}
import scala.concurrent.Future
import scala.jdk.CollectionConverters.CollectionHasAsScala

@Singleton
class AccessPointController @Inject()(cc: ControllerComponents,
                                      pds: ProxyDataSource,
                                      env: Environment,
                                      actorSystem: akka.actor.ActorSystem)
  extends AbstractController(cc) {
  /** Blocking Mongo/file work stays off Play's default pool (see app.play.conf). */
  private implicit val blockingEc: scala.concurrent.ExecutionContext =
    actorSystem.dispatchers.lookup("contexts.blocking-io-dispatcher")


  def byFloor(): Action[AnyContent] = Action.async {
    implicit request =>
      def inner(request: Request[AnyContent]): Result = {
        val anyReq = new OAuth2Request(request)
        if (!anyReq.assertJsonBody()) return RESPONSE.BAD(RESPONSE.ERROR_JSON_PARSE)
        val json = anyReq.getJsonBody()
        LOG.D2("AccessPointController: byFloor: " + Utils.stripJsValueStr(json))
        val checkRequirements = VALIDATE.checkRequirements(json, SCHEMA.fBuid, SCHEMA.fFloor)
        if (checkRequirements != null) return checkRequirements
        val buid = (json \ SCHEMA.fBuid).as[String]
        val floor = (json \ SCHEMA.fFloor).as[String]
        val APs = pds.db.getCachedAPsByBuildingFloor(buid, floor)
        // if cached return it
        if (APs != null) {
          val cached = (APs \ "accessPoints").asOpt[List[JsValue]].getOrElse(return RESPONSE.ERROR_INTERNAL("Could not retrieve access points."))
          val res = Json.obj("accessPoints" -> cached)
          return RESPONSE.gzipJsonOk(res, "Fetched precompute of accessPointsWifi")
        } else {
          try {
            val accessPoints = pds.db.getAPsByBuildingFloor(buid, floor)
            LOG.D3("mdb " + accessPoints.size)
            val uniqueAPs: util.HashMap[String, JsValue] = new util.HashMap()
            for (accessPoint <- accessPoints) {
              var tempAP = accessPoint
              var id = (tempAP \ "AP").as[String]
              id = id.substring(0, id.length - 9)
              var ap = uniqueAPs.get(id)
              val avg = (tempAP \ "RSS" \ "average").as[Double]
              val x = (tempAP \ SCHEMA.fX).as[String].toDouble
              val y = (tempAP \ SCHEMA.fY).as[String].toDouble
              if (ap == null) {
                if (avg < -60) {
                  tempAP = tempAP.as[JsObject] + ("den" -> JsNumber(avg)) + (SCHEMA.fX -> JsNumber(avg * x)) + (SCHEMA.fY -> JsNumber(avg * y))
                } else {
                  tempAP = tempAP.as[JsObject] + ("den" -> JsNumber(0)) + (SCHEMA.fX -> JsNumber(x)) + (SCHEMA.fY -> JsNumber(y))
                }
                ap = tempAP
              } else if ((ap \ "den").as[Double] < 0) {
                if (avg < -60) {
                  val ap_den = (ap \ "den").as[Double]
                  val ap_x = (ap \ SCHEMA.fX).as[Double]
                  val ap_y = (ap \ SCHEMA.fY).as[Double]
                  tempAP = tempAP.as[JsObject] + ("den" -> JsNumber(avg + ap_den)) +
                    (SCHEMA.fX -> JsNumber(avg * x + ap_x)) + (SCHEMA.fY -> JsNumber(avg * y + ap_y))
                } else {
                  tempAP = tempAP.as[JsObject] + ("den" -> JsNumber(0)) + (SCHEMA.fX -> JsNumber(x)) + (SCHEMA.fY -> JsNumber(y))
                }
                ap = tempAP
              }
              //overwrite old object in case that there is one
              uniqueAPs.put(id, ap.as[JsObject])
            }

            if (accessPoints == null) return RESPONSE.BAD_CANNOT_RETRIEVE_SPACE
            val newAccessPoint = Json.obj(SCHEMA.fBuid -> buid, SCHEMA.fFloor -> floor, "accessPoints" -> uniqueAPs.values().asScala)
            pds.db.addJson(SCHEMA.cAccessPointsWifi, newAccessPoint)
            val res: JsValue = Json.obj("accessPoints" -> new util.ArrayList[JsValue](uniqueAPs.values()).asScala)
            try {
              RESPONSE.gzipJsonOk(res, "Generated precompute of accessPointsWifi")
            } catch {
              case ioe: IOException => return RESPONSE.OK(res, "Successfully retrieved all radio points.")
            }
          } catch {
            case _: Exception => return RESPONSE.ERROR_INTERNAL("Could not retrieve access points.")
          }
        }
      }

      Future { inner(request) }(blockingEc)
  }

  /**
   * @return
   */
  def getIDs: Action[AnyContent] = Action.async {
    implicit request =>
      def inner(request: Request[AnyContent]): Result = {
        val anyReq = new OAuth2Request(request)
        if (!anyReq.assertJsonBody()) return RESPONSE.BAD(RESPONSE.ERROR_JSON_PARSE)
        val json = anyReq.getJsonBody()
        val accessPointsOfReq = (json \ "ids").asOpt[List[String]].getOrElse(null)
        if (accessPointsOfReq == null) return RESPONSE.MISSING_FIELDS(java.util.Collections.singletonList("ids"))
        try {
          val reqFile = "public/anyplace_architect/ids.json"
          val apIdsOpt = AccessPointIdsCache.lookup(accessPointsOfReq, () => env.classLoader.getResourceAsStream(reqFile))
          if (apIdsOpt.isEmpty) return RESPONSE.NOT_FOUND("Access points not found.")
          val res: JsValue = Json.obj("accessPoints" -> apIdsOpt.get)
          try {
            RESPONSE.gzipJsonOk(res.toString)
          } catch {
            case _: IOException => return RESPONSE.OK(res, "Successfully retrieved IDs for Access Points.")
          }
        } catch {
          case _: DatasourceException => return RESPONSE.ERROR_INTERNAL("Could not retrieve access points.")
        }
      }

      Future { inner(request) }(blockingEc)
  }
}
