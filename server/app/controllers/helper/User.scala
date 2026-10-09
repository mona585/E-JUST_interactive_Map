/*
 * Anyplace: A free and open Indoor Navigation Service with superb accuracy!
 *
 * Anyplace is a first-of-a-kind indoor information service offering GPS-less
 * localization, navigation and search inside buildings using ordinary smartphones.
 *
 * Author(s): Nikolas Neofytou, Paschalis Mpeis
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
package controllers.helper

import datasources.{MongodbDatasource, ProxyDataSource, SCHEMA}
import play.api.Configuration

import javax.inject.{Inject, Singleton}
import play.api.libs.json.{JsValue, Json}
import utils.{LOG, Network}

import java.security.{MessageDigest, SecureRandom}
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec
import java.util.Base64

@Singleton
class User @Inject()(pds: ProxyDataSource,
                     conf: Configuration){


  /**
   * Calls Google API to verify a Google users access token, which was sent by the client.
   *
   * @param authToken Google Authentication Token (OAuth)
   * @return
   */
  def verifyGoogleUser(authToken: String): String = {
    LOG.D3("User: verifyGoogleUser")
    if (authToken == null || authToken.trim.isEmpty) return null
    // remove the double string quotes due to json processing
    val gURL = "https://www.googleapis.com/oauth2/v3/tokeninfo?id_token=" + authToken
    var res = ""
    try {
      res = Network.GET(gURL)
    } catch {
      case e: Exception => LOG.E("verifyId", e)
    }
    if (res != null && res.nonEmpty) {
      try {
        return validateGoogleTokenInfo(Json.parse(res),
          conf.getOptional[String]("google.client.id").filter(_.nonEmpty))
      } catch {
        case iae: IllegalArgumentException => LOG.E("verifyId: " + iae.getMessage)
        case e: Exception => LOG.E("verifyId", e)
      }
    } else {
      LOG.E("User: VerifyGoogleUser: failed.")
    }
    null
  }

  /** Pure claims check over a tokeninfo document (spec-covered, no network).
   *  Google's endpoint already rejects bad signatures; we additionally demand
   *  a subject, a live token, and — when `google.client.id` is configured —
   *  an audience equal to our client ID (tokens minted for other apps must
   *  never log into ours). Unset client ID = aud skipped with a warning;
   *  the host MUST set it for production (see app.private.example.conf).
   *  @return the stable Google user id, or null. */
  def validateGoogleTokenInfo(json: JsValue, clientId: Option[String]): String = {
    val aud = (json \ "aud").asOpt[String].orElse((json \ "audience").asOpt[String])
    clientId match {
      case Some(id) if aud.getOrElse("") != id =>
        LOG.W("verifyGoogleUser: audience mismatch")
        return null
      case None =>
        LOG.W("verifyGoogleUser: google.client.id unset, audience unchecked (dev only)")
      case _ =>
    }
    val remaining = (json \ "expires_in").asOpt[String]
      .flatMap(s => try { Some(s.toLong) } catch { case _: NumberFormatException => None })
    if (remaining.exists(_ <= 0)) {
      LOG.W("verifyGoogleUser: expired token")
      return null
    }
    val uid = (json \ "user_id").asOpt[String].orElse((json \ "sub").asOpt[String])
    uid.orNull
  }

  /**
   * Checks in database if a user exists with the access_token of the json.
   *
   * apiKey: access_token for authorization
   * @return the owner_id of the user.
   */
  def authorize(apiKey: String): String = {
    if (apiKey == null) return null
    val user = pds.db.getFromKeyAsJson(SCHEMA.cUsers, SCHEMA.fAccessToken, apiKey)
    if (user != null && tokenValid(user))
      return (user \ SCHEMA.fOwnerId).as[String]
    null
  }

  /** 30-day sliding sessions. Missing expiry = legacy token, honored. */
  val TOKEN_TTL_MS: Long = 30L * 24 * 60 * 60 * 1000

  def tokenValid(user: JsValue): Boolean = {
    (user \ SCHEMA.fTokenExpires).asOpt[String] match {
      case None => true
      case Some(exp) => try {
        System.currentTimeMillis() < exp.toLong
      } catch {
        case _: NumberFormatException => false
      }
    }
  }

  def freshExpiry(): String = (System.currentTimeMillis() + TOKEN_TTL_MS).toString

  def isAdminOrModerator(userId: String): Boolean = {
    // Admin
    if (MongodbDatasource.getAdmins.contains(userId)) return true
    else if (MongodbDatasource.getModerators.contains(userId)) return true

    false
  }

  def canAccessSpace(space: JsValue, userId: String): Boolean = {
    if (isAdminOrModerator(userId)) return true
     isSpaceOwner(space, userId) || isSpaceCoOwner(space, userId)
  }

  private def isSpaceOwner(building: JsValue, userId: String): Boolean = {

    if (building != null && (building \ SCHEMA.fOwnerId).toOption.isDefined &&
      (building \ (SCHEMA.fOwnerId)).as[String].equals(userId)) return true
    false
  }

  private def isSpaceCoOwner(building: JsValue, userId: String): Boolean = {
    if (building != null) {
      val cws = (building \ SCHEMA.fCoOwners)
      if (cws.toOption.isDefined) {
        val co_owners = cws.as[List[String]]
        for (co_owner <- co_owners) {
          if (co_owner == userId)
            return true
        }
      }
    }
    false
  }

  /** PBKDF2-HMAC-SHA256 with per-user salt. Stored as
   *  `pbkdf2$<iterations>$<base64 salt>$<base64 hash>`.
   *  Iteration count follows OWASP Password Storage minimums for
   *  PBKDF2-HMAC-SHA256 (600,000); the count is embedded per-hash so future
   *  increases only affect new passwords — verification reads the stored count.
   *  Legacy rows (64-char hex of SHA-256(global salt+password+pepper)) still
   *  verify via [[verifyPassword]] so existing accounts keep working; all new
   *  hashes use this path. Never log password material.
   */
  val PBKDF2_ITERATIONS = 600000
  val PBKDF2_KEY_BITS = 256
  val PBKDF2_SALT_BYTES = 16

  def getEncryptedPassword(password: String): String = {
    val salt = new Array[Byte](PBKDF2_SALT_BYTES)
    new SecureRandom().nextBytes(salt)
    pbkdf2(password, salt, PBKDF2_ITERATIONS)
  }

  def verifyPassword(password: String, stored: String): Boolean = {
    if (stored == null) return false
    if (stored.startsWith("pbkdf2$")) {
      try {
        val parts = stored.split("\\$", -1)
        if (parts.length != 4) return false
        val iterations = parts(1).toInt
        // Cap: a planted row must not turn a login attempt into CPU DoS.
        if (iterations <= 0 || iterations > 2000000) return false
        val salt = Base64.getDecoder.decode(parts(2))
        val expected = Base64.getDecoder.decode(parts(3))
        val spec = new PBEKeySpec(password.toCharArray, salt, iterations, expected.length * 8)
        val actual = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).getEncoded
        MessageDigest.isEqual(expected, actual)
      } catch {
        case _: Exception => false
      }
    } else {
      // Legacy: SHA-256(global salt + password + pepper). Kept read-only for old rows.
      val salt = conf.get[String]("password.salt")
      val pepper = conf.get[String]("password.pepper")
      MessageDigest.isEqual(
        encryptInternal(salt + password + pepper).getBytes("UTF-8"),
        stored.getBytes("UTF-8"))
    }
  }

  private def pbkdf2(password: String, salt: Array[Byte], iterations: Int): String = {
    val spec = new PBEKeySpec(password.toCharArray, salt, iterations, PBKDF2_KEY_BITS)
    val hash = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).getEncoded
    "pbkdf2$" + iterations + "$" +
      Base64.getEncoder.encodeToString(salt) + "$" +
      Base64.getEncoder.encodeToString(hash)
  }

  private def encryptInternal(password: String): String = {
    val algorithm: MessageDigest = MessageDigest.getInstance("SHA-256")
    val defaultBytes: Array[Byte] = password.getBytes
    algorithm.reset()
    algorithm.update(defaultBytes)
    val messageDigest: Array[Byte] = algorithm.digest
    getHexString(messageDigest)
  }

  private def getHexString(messageDigest: Array[Byte]): String = {
    val hexString: StringBuffer = new StringBuffer
    messageDigest foreach { digest =>
      val hex = Integer.toHexString(0xFF & digest)
      if (hex.length == 1) hexString.append('0') else hexString.append(hex)
    }
    hexString.toString
  }
}
