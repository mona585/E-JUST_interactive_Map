/*
 * Anyplace: A free and open Indoor Navigation Service with superb accuracy!
 *
 * Anyplace is a first-of-a-kind indoor information service offering GPS-less
 * localization, navigation and search inside buildings using ordinary smartphones.
 *
 * Author(s): Nikolas Neofytou, Constantinos Costa, Kyriakos Georgiou, Lambros Petrou
 *
 * Co-Supervisor: Paschalis Mpeis
 * Supervisor: Demetrios Zeinalipour-Yazti
 *
 * URL: https://anyplace.cs.ucy.ac.cy
 * Contact: anyplace@cs.ucy.ac.cy
 *
 * Copyright (c) 2016, Data Management Systems Lab (DMSL), University of Cyprus.
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of
 * this software and associated documentation files (the “Software”), to deal in the
 * Software without restriction, including without limitation the rights to use, copy,
 * modify, merge, publish, distribute, sublicense, and/or sell copies of the Software,
 * and to permit persons to whom the Software is furnished to do so, subject to the
 * following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS
 * OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 *
 */
package controllers

import datasources.{DatasourceException, ProxyDataSource, SCHEMA}
import models.NavResultPoint
import models.oauth.OAuth2Request
import play.api.libs.json.{JsObject, JsValue, Json}
import play.api.mvc._
import services.CampusNavigationService
import utils._
import utils.json.VALIDATE

import java.util
import java.util.{ArrayList, HashMap, List}
import javax.inject.{Inject, Singleton}
import scala.concurrent.{ExecutionContext, Future}
import scala.jdk.CollectionConverters.CollectionHasAsScala

@Singleton
class NavigationController @Inject()(cc: ControllerComponents,
                                     pds: ProxyDataSource,
                                     campusNav: CampusNavigationService,
                                     actorSystem: akka.actor.ActorSystem)
  extends AbstractController(cc) {
  val ROUTE_MAX_DISTANCE_ALLOWED = 5.0
  /** Blocking Mongo/graph work stays off Play's default pool (see app.play.conf). */
  private implicit val blockingEc: ExecutionContext =
    actorSystem.dispatchers.lookup("contexts.blocking-io-dispatcher")

  def getBuildingById: Action[AnyContent] = Action.async {
    implicit request =>
      def inner(implicit request: Request[AnyContent]): Result = {
        val anyReq = new OAuth2Request(request)
        if (!anyReq.assertJsonBody()) {
          return RESPONSE.BAD(RESPONSE.ERROR_JSON_PARSE)
        }
        val json = anyReq.getJsonBody()
        LOG.D2("getBuildingById: " + json.toString)
        val checkRequirements = VALIDATE.checkRequirements(json, SCHEMA.fBuid)
        if (checkRequirements != null) return checkRequirements
        val buid = (json \ SCHEMA.fBuid).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid buid."))
        try {
          var doc = pds.db.buildingFromKeyAsJson(buid)
          if (doc == null) {
            return RESPONSE.NOT_FOUND("Space not found.")
          }
          doc = doc.as[JsObject] - SCHEMA.fOwnerId - SCHEMA.fCoOwners - SCHEMA.fId - SCHEMA.fSchema
          return RESPONSE.OK(doc, "Successfully fetched building information.")
        } catch {
          case _: DatasourceException => return RESPONSE.ERROR_INTERNAL("Could not retrieve space.")
        }
      }

      Future { inner(request) }(blockingEc)
  }

  def getPoisById: Action[AnyContent] = Action.async {
    implicit request =>
      def inner(implicit request: Request[AnyContent]): Result = {
        val anyReq = new OAuth2Request(request)
        if (!anyReq.assertJsonBody()) {
          return RESPONSE.BAD(RESPONSE.ERROR_JSON_PARSE)
        }
        val json = anyReq.getJsonBody()
        LOG.D2("getPoisById: " + json.toString)
        val checkRequirements = VALIDATE.checkRequirements(json, SCHEMA.cPOIS)
        if (checkRequirements != null) return checkRequirements
        val puid = (json \ SCHEMA.cPOIS).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid pois id."))
        try {
          var doc = pds.db.poiFromKeyAsJson(SCHEMA.cPOIS, SCHEMA.fPuid, puid)
          if (doc == null) {
            return RESPONSE.NOT_FOUND("POI not found.")
          }
          doc = doc.as[JsObject] - SCHEMA.fOwnerId - SCHEMA.fId - SCHEMA.fSchema
          return RESPONSE.OK(doc, "Fetched POI information.")
        } catch {
          case _: DatasourceException => return RESPONSE.ERROR_INTERNAL("Could not retrieve POI.")
        }
      }

      Future { inner(request) }(blockingEc)
  }

  def getNavigationRoute: Action[AnyContent] = Action.async {
    implicit request =>
      def inner(implicit request: Request[AnyContent]): Result = {
        val anyReq = new OAuth2Request(request)
        if (!anyReq.assertJsonBody()) {
          return RESPONSE.BAD(RESPONSE.ERROR_JSON_PARSE)
        }
        val json = anyReq.getJsonBody()
        LOG.D2("getNavigationRoute: " + json.toString)
        val checkRequirements = VALIDATE.checkRequirements(json, "pois_from", "pois_to")
        if (checkRequirements != null) return checkRequirements
        val puid_from = (json \ "pois_from").asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid pois_from."))
        val puid_to = (json \ "pois_to").asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid pois_to."))
        if (puid_from.equalsIgnoreCase(puid_to)) {
          return RESPONSE.BAD("Destination and Source is the same.")
        }
        try {
          val poiFrom = pds.db.getFromKeyAsJson(SCHEMA.cPOIS, SCHEMA.fPuid, puid_from)
          if (poiFrom == null) {
            return RESPONSE.NOT_FOUND("Source POI not found.")
          }
          val poiTo = pds.db.getFromKeyAsJson(SCHEMA.cPOIS, SCHEMA.fPuid, puid_to)
          if (poiTo == null) {
            return RESPONSE.NOT_FOUND("Destination POI not found.")
          }
          val buid_from = (poiFrom \ SCHEMA.fBuid).asOpt[String].getOrElse(return RESPONSE.ERROR_INTERNAL("Invalid route data."))
          val floor_from = (poiFrom \ SCHEMA.fFloorNumber).asOpt[String].getOrElse(return RESPONSE.ERROR_INTERNAL("Invalid route data."))
          val buid_to = (poiTo \ SCHEMA.fBuid).asOpt[String].getOrElse(return RESPONSE.ERROR_INTERNAL("Invalid route data."))
          val floor_to = (poiTo \ SCHEMA.fFloorNumber).asOpt[String].getOrElse(return RESPONSE.ERROR_INTERNAL("Invalid route data."))
          var points: util.List[JsValue] = null
          if (buid_from.equalsIgnoreCase(buid_to)) {
            if (floor_from.equalsIgnoreCase(floor_to)) {
              points = navigateSameFloor(poiFrom, poiTo)
            } else {
              points = navigateSameBuilding(poiFrom, poiTo)
            }
          } else {
            return RESPONSE.BAD("Navigation between buildings not supported yet.")
          }
          val res: JsValue = Json.obj("num_of_pois" -> points.size, SCHEMA.cPOIS -> points.asScala)
          return RESPONSE.OK(res, "Plotted navigation.")
        } catch {
          case _: DatasourceException => return RESPONSE.ERROR_INTERNAL("Could not plot navigation.")
        }
      }

      Future { inner(request) }(blockingEc)
  }

  /** Outdoor campus route between POIs in `cuid`. */
  def getCampusRoute: Action[AnyContent] = Action.async {
    implicit request =>
      Future {
        val anyReq = new OAuth2Request(request)
        if (!anyReq.assertJsonBody()) {
          RESPONSE.BAD(RESPONSE.ERROR_JSON_PARSE)
        } else {
          val json = anyReq.getJsonBody()
          LOG.D2("getCampusRoute: " + json.toString)
          val checkRequirements = VALIDATE.checkRequirements(json, SCHEMA.fCampusCuid, "pois_from", "pois_to")
          if (checkRequirements != null) checkRequirements
          else {
            val cuidOpt = (json \ SCHEMA.fCampusCuid).asOpt[String].map(_.trim).filter(_.nonEmpty)
            val fromOpt = (json \ "pois_from").asOpt[String].map(_.trim).filter(_.nonEmpty)
            val toOpt = (json \ "pois_to").asOpt[String].map(_.trim).filter(_.nonEmpty)
            if (cuidOpt.isEmpty) RESPONSE.BAD("Invalid cuid.")
            else if (fromOpt.isEmpty) RESPONSE.BAD("Invalid pois_from.")
            else if (toOpt.isEmpty) RESPONSE.BAD("Invalid pois_to.")
            else {
              val cuid = cuidOpt.get
              val puid_from = fromOpt.get
              val puid_to = toOpt.get
            if (puid_from.equalsIgnoreCase(puid_to)) {
              RESPONSE.BAD("Destination and Source is the same.")
            } else try {
              val poiFrom = pds.db.getFromKeyAsJson(SCHEMA.cPOIS, SCHEMA.fPuid, puid_from)
              if (poiFrom == null) {
                RESPONSE.NOT_FOUND("Source POI not found.")
              } else {
                val poiTo = pds.db.getFromKeyAsJson(SCHEMA.cPOIS, SCHEMA.fPuid, puid_to)
                if (poiTo == null) {
                  RESPONSE.NOT_FOUND("Destination POI not found.")
                } else {
                  val buids = campusNav.campusBuids(cuid)
                  if (buids.isEmpty) {
                    RESPONSE.NOT_FOUND("Campus '" + cuid + "' not found!")
                  } else {
                    val buid_from = (poiFrom \ SCHEMA.fBuid).asOpt[String].getOrElse("")
                    val buid_to = (poiTo \ SCHEMA.fBuid).asOpt[String].getOrElse("")
                    if (!buids.contains(buid_from) || !buids.contains(buid_to)) {
                      RESPONSE.BAD("Both POIs must belong to campus '" + cuid + "'.")
                    } else {
                      val stepFree = (json \ "step_free").toOption.exists(v =>
                        v.asOpt[String].contains("true") || v.asOpt[Boolean].contains(true))
                      val points = campusNav.route(buids, poiFrom, poiTo, stepFree)
                      if (points.isEmpty) {
                        if (stepFree)
                          RESPONSE.BAD("No step-free outdoor path between the two POIs on this campus yet.")
                        else
                          RESPONSE.BAD("No outdoor path between the two POIs on this campus yet.")
                      } else {
                        val distM = campusNav.distanceMeters(points)
                        val res: JsValue = Json.obj(
                          "num_of_pois" -> points.size,
                          SCHEMA.cPOIS -> points.asScala,
                          "distance_m" -> Math.round(distM),
                          "walk_min" -> campusNav.walkMinutes(distM))
                        RESPONSE.OK(res, "Plotted campus navigation.")
                      }
                    }
                  }
                }
              }
            } catch {
              case _: DatasourceException => RESPONSE.ERROR_INTERNAL("Could not plot campus navigation.")
            }
            }
          }
        }
      }(blockingEc)
  }

  def getNavigationRouteXY: Action[AnyContent] = Action.async {
    implicit request =>
      def inner(implicit request: Request[AnyContent]): Result = {
        val anyReq = new OAuth2Request(request)
        if (!anyReq.assertJsonBody()) return RESPONSE.BAD(RESPONSE.ERROR_JSON_PARSE)
        val json = anyReq.getJsonBody()
        LOG.D2("getNavigationRouteXY: " + json.toString)
        val checkRequirements = VALIDATE.checkRequirements(json,
          SCHEMA.fCoordinatesLat, SCHEMA.fCoordinatesLon, SCHEMA.fFloorNumber,
          "pois_to")
        if (checkRequirements != null) return checkRequirements
        val coordinates_lat = (json \ SCHEMA.fCoordinatesLat).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid coordinates_lat."))
        val coordinates_lon = (json \ SCHEMA.fCoordinatesLon).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid coordinates_lon."))
        val floor_number = (json \ SCHEMA.fFloorNumber).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid floor_number."))
        val puid_to = (json \ "pois_to").asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid pois_to."))
        var res: Result = null
        try {
          val poiTo = pds.db.getFromKeyAsJson(SCHEMA.cPOIS, SCHEMA.fPuid, puid_to)
          if (poiTo == null) {
            return RESPONSE.NOT_FOUND("Destination POI not found.")
          }
          val buid_to = (poiTo \ SCHEMA.fBuid).asOpt[String].getOrElse(return RESPONSE.ERROR_INTERNAL("Invalid route data."))
          val floor_to = (poiTo \ SCHEMA.fFloorNumber).asOpt[String].getOrElse(return RESPONSE.ERROR_INTERNAL("Invalid route data."))
          val dlat = try { coordinates_lat.toDouble } catch { case _: NumberFormatException => return RESPONSE.BAD("Invalid coordinates_lat.") }
          val dlon = try { coordinates_lon.toDouble } catch { case _: NumberFormatException => return RESPONSE.BAD("Invalid coordinates_lon.") }
          val floorPois = pds.db.poisByBuildingFloorAsJson(buid_to, floor_number)
          if (0 == floorPois.size) {
            return RESPONSE.BAD("Navigation is not supported on your floor.")
          }

          var dlat2: Double = 0.0
          var dlon2: Double = 0.0
          var min_distance = java.lang.Double.POSITIVE_INFINITY
          var cdist: Double = 0.0
          // Find the closest POI to start navigation
          var startingPoi: JsValue = null
          for (poi <- floorPois) {
            val plat = try { (poi \ SCHEMA.fCoordinatesLat).asOpt[String].map(_.toDouble) } catch { case _: NumberFormatException => None }
            val plon = try { (poi \ SCHEMA.fCoordinatesLon).asOpt[String].map(_.toDouble) } catch { case _: NumberFormatException => None }
            if (plat.isEmpty || plon.isEmpty) {
              LOG.D1("Skipping POI with unparsable coordinates in route-XY search.")
            } else {
              dlat2 = plat.get
              dlon2 = plon.get
              cdist = GeoPoint.getDistanceBetweenPoints(dlon, dlat, dlon2, dlat2, "K")
              if (cdist < min_distance) {
                min_distance = cdist
                startingPoi = poi
              }
            }
          }
          if (startingPoi == null) {
            val msg = "Navigation is not supported from your position."
            return RESPONSE.BAD(msg)
          } else if (min_distance > ROUTE_MAX_DISTANCE_ALLOWED) {
            val msg = "No Navigation supported at this position: startingPoi>=5km"
            LOG.D1(msg)
            return RESPONSE.BAD(msg)
          }

          LOG.D3("Starting poi: " + (startingPoi \ SCHEMA.fPuid).asOpt[String].getOrElse("?"))
          LOG.D3("min_distance: " + min_distance)
          val buid_from = (startingPoi \ SCHEMA.fBuid).asOpt[String].getOrElse(return RESPONSE.ERROR_INTERNAL("Invalid route data."))
          val floor_from = (startingPoi \ SCHEMA.fFloorNumber).asOpt[String].getOrElse(return RESPONSE.ERROR_INTERNAL("Invalid route data."))
          var points: util.List[JsValue] = null
          if (buid_from.equalsIgnoreCase(buid_to)) {
            points = if (floor_from.equalsIgnoreCase(floor_to)) navigateSameFloor(startingPoi, poiTo)
            else navigateSameBuilding(startingPoi, poiTo)
          } else {
            val msg  = "Navigation between buildings not supported yet."
            return RESPONSE.BAD(msg)
          }
          val json: JsValue = Json.obj("num_of_pois" -> points.size, SCHEMA.cPOIS -> points.asScala)
          return RESPONSE.OK(json, "Successfully plotted navigation.")
        } catch {
          case _: DatasourceException => return RESPONSE.ERROR_INTERNAL("Could not plot navigation.")
          case _: NumberFormatException => return RESPONSE.BAD("Invalid coordinate value.")
        }
      }

      Future { inner(request) }(blockingEc)
  }

  private def navigateSameFloor(from: JsValue, to: JsValue): List[JsValue] = {
    val buid = (from \ SCHEMA.fBuid).asOpt[String].getOrElse(return new util.ArrayList[JsValue]())
    val floor = (from \ SCHEMA.fFloorNumber).asOpt[String].getOrElse(return new util.ArrayList[JsValue]())
    val entry = NavigationDataCache.getOrLoad(NavigationDataCache.floorKey(buid, floor)) {
      // A same-floor route can only use same-floor edges; loading every edge in
      // the building adds no reachable nodes and needlessly grows the graph.
      val edges = new util.ArrayList[HashMap[String, String]]()
      pds.db.connectionsByBuildingFloorAsJson(buid, floor)
        .foreach(j => edges.add(JsonUtils.getHashMapStrStr(j)))
      (pds.db.poisByBuildingFloorAsMap(buid, floor), edges)
    }
    navigateSameFloor(from, to, entry.pois, entry.edges)
  }

  private def navigateSameFloor(from: JsValue, to: JsValue,
                                floorPois: util.List[HashMap[String, String]],
                                floorEdges: util.List[HashMap[String, String]]): util.List[JsValue] = {
    val puidFrom = (from \ SCHEMA.fPuid).asOpt[String].getOrElse(return new util.ArrayList[JsValue]())
    val puidTo = (to \ SCHEMA.fPuid).asOpt[String].getOrElse(return new util.ArrayList[JsValue]())
    val graph = new Dijkstra.Graph()
    graph.addPois(floorPois)
    graph.addEdges(floorEdges)
    val routePois = Dijkstra.getShortestPath(graph, puidFrom, puidTo)

    val final_points = new util.ArrayList[JsValue]()
    var p: NavResultPoint = null
    for (poi <- routePois.asScala) {
      p = new NavResultPoint()
      p.lat = poi.get(SCHEMA.fCoordinatesLat)
      p.lon = poi.get(SCHEMA.fCoordinatesLon)
      p.puid = poi.get(SCHEMA.fPuid)
      p.buid = poi.get(SCHEMA.fBuid)
      p.floor_number = poi.get(SCHEMA.fFloorNumber)
      p.pois_type = poi.get(SCHEMA.fPoisType)
      final_points.add(p.toJson())
    }
    final_points
  }

  private def navigateSameBuilding(from: JsValue, to: JsValue): util.List[JsValue] = {
    val buid = (from \ SCHEMA.fBuid).asOpt[String].getOrElse(return new util.ArrayList[JsValue]())
    val puidFrom = (from \ SCHEMA.fPuid).asOpt[String].getOrElse(return new util.ArrayList[JsValue]())
    val puidTo = (to \ SCHEMA.fPuid).asOpt[String].getOrElse(return new util.ArrayList[JsValue]())
    val entry = NavigationDataCache.getOrLoad(NavigationDataCache.buildingKey(buid)) {
      (pds.db.poisByBuildingAsMap(buid), pds.db.connectionsByBuildingAsMap(buid))
    }
    val graph = new Dijkstra.Graph()
    graph.addPois(entry.pois)
    graph.addEdges(entry.edges)
    val routePois = Dijkstra.getShortestPath(graph, puidFrom, puidTo)
    val final_points = new util.ArrayList[JsValue]()
    var p: NavResultPoint = null
    for (poi <- routePois.asScala) {
      p = new NavResultPoint()
      p.lat = poi.get(SCHEMA.fCoordinatesLat)
      p.lon = poi.get(SCHEMA.fCoordinatesLon)
      p.puid = poi.get(SCHEMA.fPuid)
      p.buid = poi.get(SCHEMA.fBuid)
      p.floor_number = poi.get(SCHEMA.fFloorNumber)
      final_points.add(p.toJson())
    }
    final_points
  }
}
