/*
 * Anyplace: A free and open Indoor Navigation Service with superb accuracy!
 *
 * Anyplace is a first-of-a-kind indoor information service offering GPS-less
 * localization, navigation and search inside buildings using ordinary smartphones.
 *
 * Author(s): Paschalis Mpeis, Constantinos Costa, Kyriakos Georgiou, Lambros Petrou
 *
 * Supervisor: Demetrios Zeinalipour-Yazti
 *
 * URL: https://anyplace.cs.ucy.ac.cy
 * Contact: anyplace@cs.ucy.ac.cy
 *
 * Copyright (c) 2021, Data Management Systems Lab (DMSL), University of Cyprus.
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

import com.typesafe.config.ConfigFactory
import play.api.Logger

object LOG {
  val logger: Logger = Logger(this.getClass)
  // Public exposure: keep runtime level visible, but avoid double Config load divergence
  // LEVEL is read once at class init; Play Configuration overrides are applied via injected config elsewhere where needed.
  val LEVEL: Int = try { ConfigFactory.load().getInt("application.debug.level") } catch { case _: Exception => 2 }

  def D(message: String): Unit = logger.debug(message)
  def I(message: String): Unit = logger.info(message)
  def W(message: String): Unit = logger.warn(message)
  def E(message: String): Unit = logger.error(message)

  def D(tag: String, message: String): Unit = D(s"$tag: $message")
  def I(tag: String, message: String): Unit = I(s"$tag: $message")
  def W(tag: String, message: String): Unit = W(s"$tag: $message")
  def E(tag: String, message: String): Unit = E(s"$tag: $message")

  def D(msg: String, e: Exception): Unit = D(s"$msg: ${prettyException(e)}")
  def I(msg: String, e: Exception): Unit = I(s"$msg: ${prettyException(e)}")
  def E(msg: String, e: Exception): Unit = E(s"$msg: ${prettyException(e)}")

  def E(tag:String, msg: String, e: Exception): Unit = E(s"$tag: $msg", e)
  def I(tag:String, msg: String, e: Exception): Unit = I(s"$tag: $msg", e)
  def D(tag:String, msg: String, e: Exception): Unit = D(s"$tag: $msg", e)


  // Helper methods
  private def prettyException(e: Exception): String= {
    val sw = new java.io.StringWriter()
    e.printStackTrace(new java.io.PrintWriter(sw))
    s"${e.getClass.getName}: ${e.getMessage}\n${sw.toString}"
  }

  def D1: Boolean = LEVEL >= 1
  def D2: Boolean = LEVEL >= 2
  def D3: Boolean = LEVEL >= 3
  def D4: Boolean = LEVEL >= 4
  def D5: Boolean = LEVEL >= 5

  // Campus optimization: by-name parameters avoid String allocation and JSON serialization when level disabled
  def D1(message: => String): Unit = if (D1) logger.warn(message)
  def D2(message: => String): Unit = if (D2) logger.debug(message)
  def D3(message: => String): Unit = if (D3) logger.debug(message)
  def D4(message: => String): Unit = if (D4) logger.debug(message)
  def D5(message: => String): Unit = if (D5) logger.debug(message)
}
