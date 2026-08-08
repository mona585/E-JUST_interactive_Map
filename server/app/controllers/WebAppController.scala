/*
 * Anyplace: A free and open Indoor Navigation Service with superb accuracy!
 *
 * Anyplace is a first-of-a-kind indoor information service offering GPS-less
 * localization, navigation and search inside buildings using ordinary smartphones.
 *
 * Author(s): Constantinos Costa, Kyriakos Georgiou, Lambros Petrou
 *
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

import datasources.SCHEMA
import play.api.Environment
import play.api.mvc.{AbstractController, Action, AnyContent, ControllerComponents, Result, RequestHeader}
//import play.Play
import javax.inject.{Inject, Singleton}

@Singleton
class WebAppController @Inject()(cc: ControllerComponents,
                                 env: Environment) extends AbstractController(cc) {

  def serveDevelopers(file: String): Action[AnyContent] = Action {
    val devsDir = "public/developers"
    serveFile(devsDir, file)
  }

  def redirectToArchitect(): Action[AnyContent] = Action {
    Redirect("/architect/")
  }

  def AddTrailingSlash(): Action[AnyContent] = Action { implicit request =>
    MovedPermanently(request.path + "/")
  }

  def serveArchitect(file: String): Action[AnyContent] = Action { implicit request =>
    val archiDir = "public/anyplace_architect"
    serveFile(archiDir, file)
  }

  def serveViewer(file: String): Action[AnyContent] = Action { implicit request =>
    val mode = request.getQueryString("mode").getOrElse("")
    var viewerDir = "public/anyplace_viewer"
    if (mode == null || !mode.equalsIgnoreCase("widget")) {
      var bid = request.getQueryString("buid").getOrElse("")
      var pid = request.getQueryString("selected").getOrElse("")
      var floor = request.getQueryString(SCHEMA.fFloor).getOrElse("")
      var campus = request.getQueryString(SCHEMA.fCampusCuid).orNull

      if (null == campus) {
        campus = ""
        viewerDir = "public/anyplace_viewer"
      } else {
        viewerDir = "public/anyplace_viewer_campus"
      }

    }
    serveFile(viewerDir, file)
  }

  def serveFile(appDir: String, file_in: String)(implicit request: RequestHeader = null): Result = {
    val file_str = if (file_in == null || file_in.trim.isEmpty || file_in.trim == "/") "index.html" else file_in.trim
    val reqFile: String = appDir + "/" + file_str
    val subPath: String = reqFile.stripPrefix("public/")

    val reqPathSubPath: Option[String] = if (request != null && request.path != null && request.path.nonEmpty) {
      val rawPath = request.path.stripPrefix("/")
      val appName = appDir.stripPrefix("public/")
      Some(s"$appName/$rawPath")
    } else None

    // 1. Try loading from ClassLoader resource (packaged JAR)
    val resourceStream = env.classLoader.getResourceAsStream(reqFile)
    if (resourceStream != null) {
      try {
        val bytes = resourceStream.readAllBytes()
        resourceStream.close()
        return Ok(bytes).as(getMimeType(file_str))
      } catch {
        case _: Exception => // fallback to file system search
      }
    }

    // 2. Comprehensive physical disk search
    val altSubPath = reqPathSubPath.getOrElse(subPath)
    val searchPaths = List(
      new java.io.File(env.rootPath, reqFile),
      new java.io.File(env.rootPath, "public/" + subPath),
      new java.io.File(env.rootPath, "public/" + altSubPath),
      new java.io.File(env.rootPath, "../server/public/" + subPath),
      new java.io.File(env.rootPath, "../server/public/" + altSubPath),
      new java.io.File(env.rootPath, "../clients/web/" + subPath),
      new java.io.File(env.rootPath, "../clients/web/" + altSubPath),
      new java.io.File(env.rootPath, "../../clients/web/" + subPath),
      new java.io.File(env.rootPath, "../../clients/web/" + altSubPath),
      new java.io.File(env.rootPath, "../../../clients/web/" + subPath),
      new java.io.File(env.rootPath, "../../../clients/web/" + altSubPath),
      new java.io.File(env.rootPath, "../../../../clients/web/" + subPath),
      new java.io.File(env.rootPath, "../../../../clients/web/" + altSubPath),
      new java.io.File("clients/web/" + subPath),
      new java.io.File("clients/web/" + altSubPath),
      new java.io.File("../clients/web/" + subPath),
      new java.io.File("../clients/web/" + altSubPath),
      new java.io.File("server/" + reqFile),
      new java.io.File("server/public/" + subPath),
      new java.io.File("server/public/" + altSubPath),
      new java.io.File(reqFile),
      new java.io.File("public/" + subPath),
      new java.io.File("public/" + altSubPath)
    )

    searchPaths.find(f => f.exists() && f.isFile) match {
      case Some(foundFile) =>
        try {
          val bytes = java.nio.file.Files.readAllBytes(foundFile.toPath)
          Ok(bytes).as(getMimeType(file_str))
        } catch {
          case e: Exception =>
            utils.LOG.E(s"Error reading file ${foundFile.getAbsolutePath}: ${e.getMessage}")
            NotFound(s"Error reading file: $file_str")
        }
      case None =>
        utils.LOG.E(s"File NOT found anywhere for reqFile: $reqFile. Searched paths: ${searchPaths.map(_.getAbsolutePath).mkString(", ")}")
        NotFound(s"File not found: $file_str in $appDir")
    }
  }

  private def getMimeType(fileName: String): String = {
    val ext = if (fileName.contains(".")) fileName.substring(fileName.lastIndexOf('.') + 1).toLowerCase else ""
    ext match {
      case "html" | "htm" => "text/html; charset=utf-8"
      case "js"           => "application/javascript; charset=utf-8"
      case "css"          => "text/css; charset=utf-8"
      case "json"         => "application/json; charset=utf-8"
      case "png"          => "image/png"
      case "jpg" | "jpeg" => "image/jpeg"
      case "gif"          => "image/gif"
      case "svg"          => "image/svg+xml"
      case "ico"          => "image/x-icon"
      case "woff"         => "font/woff"
      case "woff2"        => "font/woff2"
      case "ttf"          => "font/ttf"
      case _              => "application/octet-stream"
    }
  }
}