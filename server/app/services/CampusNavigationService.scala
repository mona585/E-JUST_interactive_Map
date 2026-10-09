package services

import datasources.{ProxyDataSource, SCHEMA}
import models.NavResultPoint
import play.api.libs.json.JsValue
import utils.Dijkstra

import java.util
import javax.inject.{Inject, Singleton}
import scala.jdk.CollectionConverters.CollectionHasAsScala

/**
 * Campus (building-to-building) routing — the outdoor pilot's core.
 *
 * Unlike the indoor paths in [[controllers.NavigationController]] (same floor /
 * same building over hallway/stair/elevator edges), this routes across the
 * outdoor connector graph of a whole campus: every POI of every member Space
 * becomes a vertex, every `outdoor` edge whose endpoints both sit inside the
 * campus becomes an undirected weighted edge, Dijkstra does the rest.
 *
 * Response shape mirrors the indoor endpoints (`num_of_pois` + `pois[]` of
 * [[models.NavResultPoint]] JSON) so clients draw campus legs with the same
 * polyline code, keyed by `buid` + `floor_number`.
 */
@Singleton
class CampusNavigationService @Inject() (pds: ProxyDataSource) {

  def campusBuids(cuid: String): List[String] =
    pds.db.getBuildingSet(cuid)
      .flatMap(c => (c \ SCHEMA.fBuids).asOpt[List[String]].getOrElse(Nil))
      .distinct

  /** Empty list = no outdoor path; callers decide how to report it. */
  def route(cuid: String, fromPoi: JsValue, toPoi: JsValue): util.List[JsValue] =
    route(campusBuids(cuid), fromPoi, toPoi)

  /** buids pre-resolved by the caller: one campus read per request, no TOCTOU skew. */
  def route(buids: List[String], fromPoi: JsValue, toPoi: JsValue): util.List[JsValue] = {
    val points = new util.ArrayList[JsValue]()
    if (buids.isEmpty) return points
    val fromPuid = (fromPoi \ SCHEMA.fPuid).asOpt[String].orNull
    val toPuid = (toPoi \ SCHEMA.fPuid).asOpt[String].orNull
    if (fromPuid == null || toPuid == null) return points
    val graph = new Dijkstra.Graph()
    for (buid <- buids) {
      for (poi <- pds.db.poisByBuildingAsMap(buid).asScala) graph.addPoi(poi)
    }
    graph.addEdges(pds.db.connectionsByCampusAsMap(buids))
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
}
