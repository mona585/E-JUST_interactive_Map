package services

import datasources.{ProxyDataSource, SCHEMA}
import models.NavResultPoint
import play.api.libs.json.JsValue
import utils.{Dijkstra, NavigationDataCache}

import java.util
import javax.inject.{Inject, Singleton}
import scala.jdk.CollectionConverters.CollectionHasAsScala

/** Campus building-to-building routing over outdoor connectors via Dijkstra; response mirrors indoor endpoints. */
@Singleton
class CampusNavigationService @Inject() (pds: ProxyDataSource) {

  def campusBuids(cuid: String): List[String] =
    pds.db.getBuildingSet(cuid)
      .flatMap(c => (c \ SCHEMA.fBuids).asOpt[List[String]].getOrElse(Nil))
      .distinct

  /** Empty list = no outdoor path; callers decide how to report it. */
  def route(cuid: String, fromPoi: JsValue, toPoi: JsValue): util.List[JsValue] =
    route(campusBuids(cuid), fromPoi, toPoi)

  /** Empty list = no outdoor path; callers decide how to report it.
   *  `stepFree` drops stair edges (elevators stay) for accessible routing. */
  def route(buids: List[String], fromPoi: JsValue, toPoi: JsValue,
            stepFree: Boolean = false): util.List[JsValue] = {
    val points = new util.ArrayList[JsValue]()
    if (buids.isEmpty) return points
    val fromPuid = (fromPoi \ SCHEMA.fPuid).asOpt[String].orNull
    val toPuid = (toPoi \ SCHEMA.fPuid).asOpt[String].orNull
    if (fromPuid == null || toPuid == null) return points
    val entry = NavigationDataCache.getOrLoad(NavigationDataCache.campusKey(buids)) {
      (pds.db.poisByBuildingIdsAsMap(buids), pds.db.connectionsByCampusAsMap(buids))
    }
    val graph = new Dijkstra.Graph()
    for (poi <- entry.pois.asScala) graph.addPoi(poi)
    val edges = entry.edges.asScala.filterNot { e =>
      stepFree && "stair".equalsIgnoreCase(e.get(SCHEMA.fEdgeType))
    }
    val edgeList = new util.ArrayList[util.HashMap[String, String]]()
    edges.foreach(edgeList.add)
    graph.addEdges(edgeList)
    val routePois = Dijkstra.getShortestPath(graph, fromPuid, toPuid)

    for (poi <- routePois.asScala) {
      val p = new NavResultPoint()
      p.lat = poi.get(SCHEMA.fCoordinatesLat)
      p.lon = poi.get(SCHEMA.fCoordinatesLon)
      p.puid = poi.get(SCHEMA.fPuid)
      p.buid = poi.get(SCHEMA.fBuid)
      p.floor_number = poi.get(SCHEMA.fFloorNumber)
      p.pois_type = poi.get(SCHEMA.fPoisType)
      points.add(p.toJson())
    }
    points
  }

  /** Walking distance in meters over consecutive route points. */
  def distanceMeters(points: util.List[JsValue]): Double = {
    var total = 0.0
    val it = points.asScala.toList
    for (pair <- it.zip(it.drop(1))) {
      try {
        val aLat = (pair._1 \ "lat").as[String].toDouble
        val aLon = (pair._1 \ "lon").as[String].toDouble
        val bLat = (pair._2 \ "lat").as[String].toDouble
        val bLon = (pair._2 \ "lon").as[String].toDouble
        total += utils.GeoPoint.getDistanceBetweenPoints(aLon, aLat, bLon, bLat, "K") * 1000.0
      } catch {
        case _: Exception => // unparseable leg contributes nothing
      }
    }
    total
  }

  /** Walking minutes at 80 m/min, minimum 1. */
  def walkMinutes(distanceM: Double): Int = Math.max(1, Math.round(distanceM / 80.0).toInt)
}
