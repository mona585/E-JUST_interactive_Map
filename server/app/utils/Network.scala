package utils

import java.io.{BufferedReader, InputStreamReader}
import java.net.{HttpURLConnection, URL}

object Network {

  /**
   * GET request
   *
   * @param url
   * @return
   */
  def GET(url: String, connectTimeoutMs: Int = 8000, readTimeoutMs: Int = 8000) = {
    val obj = new URL(url)
    val con = obj.openConnection().asInstanceOf[HttpURLConnection]
    con.setRequestMethod("GET")
    con.setConnectTimeout(connectTimeoutMs)
    con.setReadTimeout(readTimeoutMs)
    val code = con.getResponseCode
    if (code < 200 || code >= 300)
      throw new java.io.IOException("GET " + url.split("\\?")(0) + " returned HTTP " + code)
    val in = new BufferedReader(new InputStreamReader(con.getInputStream))
    try {
      val response = new StringBuffer()
      response.append(Iterator.continually(in.readLine()).takeWhile(_ != null).mkString)
      response.toString
    } finally {
      in.close()
      con.disconnect()
    }
  }

}
