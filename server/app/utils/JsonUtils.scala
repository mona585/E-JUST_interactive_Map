/*
 * AnyPlace: A free and open Indoor Navigation Service with superb accuracy!
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
package utils

import java.util
import java.util.{Collections, HashMap}

import datasources.SCHEMA
import org.bson.{BsonDocument, BsonType, BsonValue}
import play.api.libs.json.{JsArray, JsBoolean, JsNull, JsNumber, JsObject, JsString, JsValue, Json}

import scala.jdk.CollectionConverters._

object JsonUtils {


  def getHashMapStrStr(json: JsValue): HashMap[String, String] = {
    val result = new HashMap[String, String]()
    json.asOpt[JsObject].foreach(_.fields.foreach { case (key, value) =>
      val converted = value match {
        case JsString(string) => string
        case JsNumber(number) => number.toString
        case JsBoolean(boolean) => boolean.toString
        case JsNull => null
        case other => Json.stringify(other)
      }
      result.put(key, converted)
    })
    result
  }

  def hasProperties(json: JsValue, keys: String*): util.List[String] = {
    if (json == null) {
      throw new IllegalArgumentException("No source Json object or destination Map object can be null!")
    }
    if (keys == null) {
      return Collections.emptyList()
    }
    val notFound = new util.ArrayList[String]()
    for (k <- keys) {
      val value = json \ k
      if (value == null)
        notFound.add(k)
      else {
        val svalue = value.asOpt[String].getOrElse("")
        if (svalue.isEmpty) {
          val avalue = value.asOpt[JsArray].orNull
          if (avalue == null) {
            val ovalue = value.asOpt[JsValue].orNull
            if (ovalue == null)
            notFound.add(k)
          }
        }
      }
    }
    notFound
  }

  def hasProperty(json: JsValue, key: String): Boolean = {
    if (json == null) {
      throw new IllegalArgumentException("No source Json object or destination Map object can be null!")
    }
    if (key == null) {
      return false
    }
    val value = json \ key
    return value.toOption.isDefined
  }

  def convertToInt(key: String, json: JsValue): JsValue = {
    var value = "0"
    if ((json \ key).toOption.isDefined)
      value = (json \ key).as[String]
    json.as[JsObject] + (key -> JsNumber(value.toInt))
  }

  def isNullOrEmpty(x: JsValue): Boolean = {
    if (x == null)
      return true
    if (Json.stringify(x) == "{}" || Json.stringify(x) == "")
      return true
    return false
  }

  def cleanupMongoJson(json: JsValue): JsValue = {
    return json.as[JsObject] - SCHEMA.fId - SCHEMA.fSchema
  }

  def mongoDocumentToJson(document: BsonDocument): JsObject = {
    JsObject(document.entrySet().asScala.collect {
      case entry if entry.getKey != SCHEMA.fId && entry.getKey != SCHEMA.fSchema =>
        entry.getKey -> bsonToJson(entry.getValue)
    }.toSeq)
  }

  def bsonToJson(value: BsonValue): JsValue = {
    if (value == null) return JsNull
    value.getBsonType match {
      case BsonType.NULL => JsNull
      case BsonType.BOOLEAN => JsBoolean(value.asBoolean().getValue)
      case BsonType.STRING => JsString(value.asString().getValue)
      case BsonType.INT32 => JsNumber(value.asInt32().getValue)
      case BsonType.INT64 => JsNumber(BigDecimal(value.asInt64().getValue))
      case BsonType.DOUBLE => JsNumber(BigDecimal(value.asDouble().getValue))
      case BsonType.DECIMAL128 => JsNumber(value.asDecimal128().getValue.bigDecimalValue())
      case BsonType.OBJECT_ID => Json.obj("$oid" -> value.asObjectId().getValue.toHexString)
      case BsonType.ARRAY => JsArray(value.asArray().getValues.asScala.map(bsonToJson).toSeq)
      case BsonType.DOCUMENT => JsObject(value.asDocument().entrySet().asScala.map { entry =>
        entry.getKey -> bsonToJson(entry.getValue)
      }.toSeq)
      case _ => Json.parse(new BsonDocument("v", value).toJson()).as[JsObject].value("v")
    }
  }

}
