package controllers

import java.security.MessageDigest
import datasources.MongodbDatasource.updateCachedModerators
import datasources.{MongodbDatasource, ProxyDataSource, SCHEMA}

import javax.inject.{Inject, Singleton}
import utils.json.VALIDATE
import models.{Account, ExternalType}
import models.ExternalType.ExternalType
import models.oauth.OAuth2Request
import play.api.Configuration
import play.api.libs.json._
import play.api.mvc._
import utils.JsonUtils.isNullOrEmpty
import utils.{JsonUtils, LOG, Network, RESPONSE, Utils}

@Singleton
class UserController @Inject()(cc: ControllerComponents,
                               pds: ProxyDataSource,
                               userHelper: helper.User)
  extends AbstractController(cc) {


  def register(): Action[AnyContent] = Action {
    implicit request =>
      def inner(request: Request[AnyContent]): Result = {
        val anyReq: OAuth2Request = new OAuth2Request(request)
        if (!anyReq.assertJsonBody()) return RESPONSE.BAD(RESPONSE.ERROR_JSON_PARSE)
        val json = anyReq.getJsonBody()
        LOG.D4("register request received")
        val checkRequirements = VALIDATE.checkRequirements(json, SCHEMA.fUsername, SCHEMA.fPassword, SCHEMA.fName, SCHEMA.fEmail)
        if (checkRequirements != null) return checkRequirements
        val name = (json \ SCHEMA.fName).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid name."))
        val email = (json \ SCHEMA.fEmail).asOpt[String].map(_.trim.toLowerCase)
          .filter(_.matches("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$"))
          .getOrElse(return RESPONSE.BAD("Invalid email."))
        val username = (json \ SCHEMA.fUsername).asOpt[String].map(_.trim)
          .filter(_.matches("^[A-Za-z0-9._-]{3,32}$"))
          .getOrElse(return RESPONSE.BAD("Invalid username."))
        val password = (json \ SCHEMA.fPassword).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid password."))
        val external = "anyplace"
        var accType = "user"

        // if first user then assign as admin
        if (pds.db.isAdmin())
          accType = "admin"
        // Uniqueness without oracle: one generic answer for taken email/username.
        val storedEmail = pds.db.getFromKeyAsJson(SCHEMA.cUsers, SCHEMA.fEmail, email)
        val storedUsername = pds.db.getFromKeyAsJson(SCHEMA.cUsers, SCHEMA.fUsername, username)
        if (storedEmail != null || storedUsername != null) return RESPONSE.BAD("Registration failed.")
        val hashed = try {
          userHelper.getEncryptedPassword(password)
        } catch {
          case _: IllegalArgumentException => return RESPONSE.BAD("Password must be 8-128 characters.")
        }
        val newUser = try {
          pds.db.register(SCHEMA.cUsers, name, email, username, hashed, external, accType)
        } catch {
          case _: Exception => return RESPONSE.ERROR_INTERNAL("Could not register.")
        }
        if (newUser == null) return RESPONSE.ERROR_INTERNAL("Could not register.")
        val res: JsValue = Json.obj("newUser" -> newUser)
        return RESPONSE.OK(res,"Successfully registered.")
      }
      inner(request)
  }


  def loginLocal(): Action[AnyContent] = Action {
    implicit request =>

      def inner(request: Request[AnyContent]): Result = {
        val anyReq: OAuth2Request = new OAuth2Request(request)
        if (!anyReq.assertJsonBody()) return RESPONSE.BAD(RESPONSE.ERROR_JSON_PARSE)
        val json = anyReq.getJsonBody()
        val checkRequirements = VALIDATE.checkRequirements(json, SCHEMA.fUsername, SCHEMA.fPassword)
        if (checkRequirements != null) return checkRequirements
        LOG.D4("local login request received")
        val username = (json \ SCHEMA.fUsername).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.UNAUTHORIZED("Incorrect username or password."))
        val password = (json \ SCHEMA.fPassword).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.UNAUTHORIZED("Incorrect username or password."))
        // Per-user PBKDF2 salts: fetch by username, then verify in code. Fall
        // back to a case-insensitive username or email match for password
        // managers and users who sign in with their email address.
        val exactDoc = pds.db.getFromKeyAsJson(SCHEMA.cUsers, SCHEMA.fUsername, username)
        val storedDoc = if (exactDoc != null) exactDoc else pds.db.getUserByIdentifier(username)
        if (storedDoc == null) return RESPONSE.UNAUTHORIZED("Incorrect username or password.")
        val storedHash = (storedDoc \ SCHEMA.fPassword).asOpt[String].orNull
        if (!userHelper.verifyPassword(password, storedHash)) return RESPONSE.UNAUTHORIZED("Incorrect username or password.")
        // Rotate expired tokens, stamp expiry on legacy ones. Rotation is
        // unconditional here: reusing a pre-expiry token would let a token
        // minted before expiry existed live on under its old value.
        var sessionDoc = storedDoc
        val expired = !userHelper.tokenValid(storedDoc)
        val missingExp = (storedDoc \ SCHEMA.fTokenExpires).asOpt[String].isEmpty
        if (expired || missingExp) {
          val token = MongodbDatasource.generateAccessToken(true)
          sessionDoc = storedDoc.as[JsObject] +
            (SCHEMA.fAccessToken -> JsString(token)) +
            (SCHEMA.fTokenExpires -> JsString(userHelper.freshExpiry()))
          val persisted = try {
            pds.db.replaceJsonDocument(SCHEMA.cUsers, SCHEMA.fUsername, username, sessionDoc.toString())
          } catch {
            case _: Exception => false
          }
          if (!persisted) return RESPONSE.ERROR_INTERNAL("Could not refresh session.")
        }
        val storedUser = List(sessionDoc)
        val accessToken = (storedUser.head \ SCHEMA.fAccessToken).asOpt[String].filter(_.nonEmpty)
          .getOrElse(return RESPONSE.ERROR_INTERNAL("User doesn't have access token."))

        val userJson = storedUser.head.as[JsObject] - SCHEMA.fPassword
        val res = Json.obj("user" -> userJson)

        updateCachedModerators()
        return RESPONSE.OK(res, "Successfully found user.")
      }

      inner(request)
  }

  def refreshLocal(): Action[AnyContent] = Action {
    implicit request =>

      def inner(request: Request[AnyContent]): Result = {
        val anyReq: OAuth2Request = new OAuth2Request(request)
        if (!anyReq.assertJsonBody()) return RESPONSE.BAD(RESPONSE.ERROR_JSON_PARSE)
        val json = anyReq.getJsonBody()
        val checkRequirements = VALIDATE.checkRequirements(json, SCHEMA.fAccessToken)
        if (checkRequirements != null) return checkRequirements
        LOG.D4("local session refresh request received")
        val accessToken = (json \ SCHEMA.fAccessToken).asOpt[String].filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid access_token."))

        val storedUser = try {
          pds.db.getUserFromAccessToken(accessToken)
        } catch {
          case _: Exception => return RESPONSE.ERROR_INTERNAL("Could not refresh session.")
        }
        if (storedUser == null || storedUser.isEmpty) return RESPONSE.UNAUTHORIZED("Invalid session.")
        if (storedUser.size > 1) return RESPONSE.ERROR_INTERNAL("Duplicate session.")
        if (!userHelper.tokenValid(storedUser.head)) return RESPONSE.UNAUTHORIZED("Session expired, please log in again.")

        // Rotation: fresh token + expiry per refresh; stolen tokens die at next refresh.
        val rotated = storedUser.head.as[JsObject] +
          (SCHEMA.fAccessToken -> JsString(MongodbDatasource.generateAccessToken(true))) +
          (SCHEMA.fTokenExpires -> JsString(userHelper.freshExpiry()))
        val rotatedOk = try {
          pds.db.replaceJsonDocument(SCHEMA.cUsers, SCHEMA.fAccessToken, accessToken, rotated.toString())
        } catch {
          case _: Exception => false
        }
        if (!rotatedOk) return RESPONSE.UNAUTHORIZED("Session rotated elsewhere, please log in again.")
        val user = rotated - SCHEMA.fPassword
        val res = Json.obj("user" -> user)

        updateCachedModerators()
        RESPONSE.OK(res, "Successfully found user.")
      }

      inner(request)
  }

  /**
   *
   * @return type(admin, user, .. etc) + message
   */
  def loginGoogle(): Action[AnyContent] = Action {
    implicit request =>
      def inner(request: Request[AnyContent]): Result = {
        LOG.D2("User: loginGoogle")
        val auth = new OAuth2Request(request)
        if (!auth.assertJsonBody()) return RESPONSE.BAD(RESPONSE.ERROR_JSON_PARSE)
        val json = auth.getJsonBody()
        if (isNullOrEmpty(json)) return RESPONSE.BAD(RESPONSE.ERROR_API_USAGE)
        val external = json \ SCHEMA.fExternal

        if (external.toOption.isDefined && external.asOpt[String].contains("google")) {
          if ((json \ SCHEMA.fAccessToken).asOpt[String].orNull == null)
            return RESPONSE.BAD("Google access_token is required.")
          val result = authorizeGoogleAccount(auth)
          updateCachedModerators()

          result
        } else {
          RESPONSE.BAD("Not a google account.")
        }
      }

      inner(request)
  }

  def updateUser(): Action[AnyContent] = Action {
    implicit request =>
      def inner(request: Request[AnyContent]): Result = {
        val anyReq = new OAuth2Request(request)
        val apiKey = anyReq.getAccessToken()
        if (apiKey == null) return anyReq.NO_ACCESS_TOKEN()
        LOG.D2("updateUser:")
        if (!anyReq.assertJsonBody()) return RESPONSE.BAD(RESPONSE.ERROR_JSON_PARSE)
        val json = anyReq.getJsonBody()
        val checkRequirements = VALIDATE.checkRequirements(json, SCHEMA.fUserId)
        if (checkRequirements != null) return checkRequirements

        val owner_id = userHelper.authorize(apiKey)
        if (owner_id == null) return RESPONSE.UNAUTHORIZED_USER

        val userOwnerId = (json \ SCHEMA.fUserId).asOpt[String].map(_.trim).filter(_.nonEmpty)
          .getOrElse(return RESPONSE.BAD("Invalid user_id."))
        // only admin can update a user, or the user can update it self
        if (owner_id != userOwnerId && !MongodbDatasource.getAdmins.contains(owner_id) && !MongodbDatasource.getModerators.contains(owner_id))
          return RESPONSE.FORBIDDEN("Users can only update themselves, unless they are moderators.")

        val storedUser = try {
          pds.db.getUserFromOwnerId(userOwnerId)
        } catch {
          case _: Exception => return RESPONSE.ERROR_INTERNAL("Could not retrieve user.")
        }
        if (storedUser == null || storedUser.isEmpty) return RESPONSE.NOT_FOUND("User not found.")
        if (storedUser.size > 1) return RESPONSE.ERROR_INTERNAL("Duplicate user.")
        var newUser: JsValue = storedUser.head
        var typeChanged = false
        val callerIsAdmin = MongodbDatasource.getAdmins.contains(owner_id)
        val isSelf = owner_id == userOwnerId
        // Privilege boundary: moderators service regular accounts only — never
        // admins, and never fellow moderators (blocks mutual elevation).
        if (!isSelf && !callerIsAdmin) {
          val targetType = (storedUser.head \ SCHEMA.fType).asOpt[String].getOrElse("user")
          if (targetType != "user" || MongodbDatasource.getAdmins.contains(userOwnerId) ||
            MongodbDatasource.getModerators.contains(userOwnerId))
            return RESPONSE.FORBIDDEN("Moderators cannot modify privileged accounts.")
        }

        if ((json \ SCHEMA.fName).toOption.isDefined) {
          newUser = newUser.as[JsObject] + (SCHEMA.fName -> JsString(
            (json \ SCHEMA.fName).asOpt[String].map(_.trim).filter(_.nonEmpty)
              .getOrElse(return RESPONSE.BAD("Invalid name."))))
        }
        if ((json \ SCHEMA.fEmail).toOption.isDefined) {
          val email = (json \ SCHEMA.fEmail).asOpt[String].map(_.trim.toLowerCase)
            .filter(_.matches("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$"))
            .getOrElse(return RESPONSE.BAD("Invalid email."))
          val storedEmail = pds.db.getFromKeyAsJson(SCHEMA.cUsers, SCHEMA.fEmail, email)
          if (storedEmail != null &&
            (storedEmail \ SCHEMA.fOwnerId).asOpt[String].exists(_ != userOwnerId))
            return RESPONSE.BAD("There is already an account with this email.")
          newUser = newUser.as[JsObject] + (SCHEMA.fEmail -> JsString(email))
        }
        if ((json \ SCHEMA.fUsername).toOption.isDefined) {
          val username = (json \ SCHEMA.fUsername).asOpt[String].map(_.trim)
            .filter(_.matches("^[A-Za-z0-9._-]{3,32}$"))
            .getOrElse(return RESPONSE.BAD("Invalid username."))
          val storedUsername = pds.db.getFromKeyAsJson(SCHEMA.cUsers, SCHEMA.fUsername, username)
          if (storedUsername != null &&
            (storedUsername \ SCHEMA.fOwnerId).asOpt[String].exists(_ != userOwnerId))
            return RESPONSE.BAD("Username is already taken.")
          newUser = newUser.as[JsObject] + (SCHEMA.fUsername -> JsString(username))
        }
        if ((json \ SCHEMA.fPassword).toOption.isDefined) {
          // Passwords are self-service or admin-only to prevent credential takeover.
          val isAdmin = MongodbDatasource.getAdmins.contains(owner_id)
          if (owner_id != userOwnerId && !isAdmin)
            return RESPONSE.FORBIDDEN("Only the user or an admin can change passwords.")
          val rawPassword = (json \ SCHEMA.fPassword).asOpt[String]
            .getOrElse(return RESPONSE.BAD("Invalid password."))
          val hashed = try {
            userHelper.getEncryptedPassword(rawPassword)
          } catch {
            case _: IllegalArgumentException => return RESPONSE.BAD("Password must be 8-128 characters.")
          }
          newUser = newUser.as[JsObject] + (SCHEMA.fPassword -> JsString(hashed))
        }
        // Only admins can change type of user
        if ((json \ SCHEMA.fType).toOption.isDefined) {
          if (MongodbDatasource.getAdmins.contains(userOwnerId))
            return RESPONSE.FORBIDDEN("Cannot change type of an admin.")
          if (callerIsAdmin) {
            val _type = (json \ SCHEMA.fType).asOpt[String]
              .getOrElse(return RESPONSE.BAD("Invalid type."))
            if (_type.equals("moderator") || _type.equals("user")) {
              newUser = newUser.as[JsObject] + (SCHEMA.fType -> JsString(_type))
              typeChanged = true
            } else {
              return RESPONSE.FORBIDDEN("Cannot change to type '" + _type + "'")
            }
          } else {
            return RESPONSE.FORBIDDEN("Unauthorized. Only admins can change user type.")
          }
        }
        if (pds.db.replaceJsonDocument(SCHEMA.cUsers, SCHEMA.fOwnerId, userOwnerId, newUser.toString())) {
          // Role caches are snapshots: a type change must publish immediately
          // or the old role keeps authorizing until the next refresh cycle.
          if (typeChanged) updateCachedModerators()
          return RESPONSE.OK("Successfully updated user.")
        }
        return RESPONSE.ERROR_INTERNAL("Could not update user.")
      }

      inner(request)
  }

  def getAccountType(json: JsValue): ExternalType = {
    if ((json \ SCHEMA.fExternal).asOpt[String].contains("google")) return ExternalType.GOOGLE
    ExternalType.LOCAL
  }

  def getGoogleUser(json: JsValue): JsValue = {
    getAccountType(json) match {
      case ExternalType.GOOGLE =>
        val ownerId = (json \ SCHEMA.fOwnerId).asOpt[String].filter(_.nonEmpty).orNull
        if (ownerId == null) {
          LOG.E("getGoogleUser: missing owner_id.")
          return null
        }
        val users = pds.db.getUserFromOwnerId(ownerId)
        if (users == null) return null
        if (users.size > 1) {
          LOG.E("User exists. More than one user with id: " + ownerId)
          return null
        }
        users.head
      case _ =>
        LOG.E("Not a Google User.")
        null
    }
  }

  /**
   * Checks that a Google user was in the database, otherwise it
   * creates a new anyplace account for that user.
   *
   * NOTE: An anyplace specific Access Token is generated for a Google User as well
   *
   * @param auth
   * @return
   */
  def authorizeGoogleAccount(auth: OAuth2Request): Result = {
    LOG.D2("User: authorizeGoogleAccount")
    var json = auth.getJsonBody()
    val hasExternal = JsonUtils.hasProperties(json, SCHEMA.fExternal) // TODO
    if (!hasExternal.isEmpty) return RESPONSE.MISSING_FIELDS(hasExternal)

    var id = userHelper.verifyGoogleUser(
      (json \ SCHEMA.fAccessToken).asOpt[String].map(_.trim).filter(_.nonEmpty).orNull)
    if (id == null || id.trim.isEmpty) return RESPONSE.UNAUTHORIZED_USER
    id = Utils.appendGoogleIdIfNeeded(id.trim)
    json = json.as[JsObject] + (SCHEMA.fOwnerId -> Json.toJson(id))

    // if user exists but has no anyplace access_token: create one and put on db
    var user = getGoogleUser(json)
    var hasAccessToken = false
    LOG.D4("authorizeGoogleAccount: hasAccessToken: " + hasAccessToken)
    if (user != null) {
      hasAccessToken = (user \ SCHEMA.fAccessToken).asOpt[String].exists(_.nonEmpty)
    }

    // Existing Google users may lack access_token (pre-MDB 4.2); generate one.
    // Expired sessions rotate here too — a returning Google login must never
    // resurrect a dead token the way the old exists-path did.
    if (user != null && (!hasAccessToken || !userHelper.tokenValid(user))) {
      LOG.D2("Generating access token for existing Google User")
      val newAccessToken = MongodbDatasource.generateAccessToken(false)
      user = user.as[JsObject] + (SCHEMA.fAccessToken -> JsString(newAccessToken)) +
        (SCHEMA.fTokenExpires -> JsString(userHelper.freshExpiry())) +
        (SCHEMA.fSchema -> JsNumber(MongodbDatasource.__SCHEMA))
      val ownerKey = (json \ SCHEMA.fOwnerId).asOpt[String].getOrElse("")
      if (ownerKey.isEmpty ||
        !pds.db.replaceJsonDocument(SCHEMA.cUsers, SCHEMA.fOwnerId, ownerKey, user.toString()))
        return RESPONSE.ERROR_INTERNAL("Could not refresh Google session.")
    }
    var userType = "user"
    if (pds.db.isAdmin()) userType = "admin"
    json = json.as[JsObject] + (SCHEMA.fOwnerId -> Json.toJson(id)) +
      (SCHEMA.fType -> JsString(userType))
    var msg=""
    if (user != null) { // user and access_token exists
      msg="User Exists."
    } else {  // new user created

      if((json \ SCHEMA.fName).asOpt[String].map(_.trim).filter(_.nonEmpty).isEmpty) {
        return RESPONSE.BAD("A name must be provided when registering new Google account.")
      }

      LOG.D2("Registering new google user..")
      val built = try {
        new Account(json).toJson()
      } catch {
        case _: Exception => return RESPONSE.BAD("Invalid Google account payload.")
      }
      if (!pds.db.addJson(SCHEMA.cUsers, built))
        return RESPONSE.ERROR_INTERNAL("Could not create Google user.")
      user = built
      msg="Created new google user."
    }

    val response = Json.obj("user" -> (user.as[JsObject] - SCHEMA.fPassword))
    RESPONSE.OK(response, msg)
  }

}

