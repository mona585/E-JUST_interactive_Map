/*
 * AnyPlace: A free and open Indoor Navigation Service with superb accuracy!
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

package utils
import play.api.Configuration

import java.net.URI
import javax.inject.{Inject, Singleton}

@Singleton
class AnyplaceServerAPI @Inject() (conf: Configuration) {
  val sep = "/"
  val PUBLIC_BASE_URL: String = normalizePublicBase(conf.get[String]("public.baseUrl"))
  val SERVER_ADDRESS: String = PUBLIC_BASE_URL
  val SERVER_PORT: String = publicPort(PUBLIC_BASE_URL)
  val SERVER_FULL_URL: String = PUBLIC_BASE_URL
  val SERVER_API_ROOT: String = SERVER_FULL_URL + sep + "api" + sep
  val ANDROID_API_ROOT: String = SERVER_API_ROOT

  def urlPath(parts: String*): String = {
    val path = parts.map(_.stripPrefix("/").stripSuffix("/")).filter(_.nonEmpty).mkString("/")
    SERVER_FULL_URL + sep + path
  }

  private def normalizePublicBase(value: String): String = {
    val trimmed = value.trim.stripSuffix("/")
    val uri = new URI(trimmed)
    if (uri.getScheme == null || uri.getHost == null) {
      throw new IllegalArgumentException("public.baseUrl must be an absolute URL")
    }
    trimmed
  }

  private def publicPort(value: String): String = {
    val uri = new URI(value)
    if (uri.getPort != -1) uri.getPort.toString
    else if (uri.getScheme == "https") "443"
    else "80"
  }
}
