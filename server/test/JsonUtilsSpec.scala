import org.bson._
import org.bson.types.ObjectId
import org.specs2.mutable.Specification
import play.api.libs.json.{JsNull, Json}
import utils.JsonUtils

class JsonUtilsSpec extends Specification {

  "JsonUtils.bsonToJson" should {

    "match the driver's relaxed JSON for common BSON values" in {
      val doc = new BsonDocument()
        .append("string", new BsonString("text"))
        .append("int", new BsonInt32(42))
        .append("long", new BsonInt64(9007199254740993L))
        .append("double", new BsonDouble(1.5))
        .append("boolean", BsonBoolean.TRUE)
        .append("null", BsonNull.VALUE)
        .append("objectId", new BsonObjectId(new ObjectId("64b7f0a1f1c2d3e4f5a6b7c8")))
        .append("array", new BsonArray(java.util.Arrays.asList(new BsonInt32(1), new BsonString("x"))))
        .append("document", new BsonDocument("key", new BsonString("value")))

      JsonUtils.bsonToJson(doc) must equalTo(Json.parse(doc.toJson()))
    }

    "fall back to the driver for dates, binary and regex values" in {
      val doc = new BsonDocument()
        .append("date", new BsonDateTime(1700000000000L))
        .append("binary", new BsonBinary(Array[Byte](1, 2, 3)))
        .append("regex", new BsonRegularExpression("^a", "i"))

      JsonUtils.bsonToJson(doc) must equalTo(Json.parse(doc.toJson()))
    }

    "drop Mongo-only root fields during document conversion" in {
      val doc = new BsonDocument()
        .append("_id", new BsonObjectId(new ObjectId("64b7f0a1f1c2d3e4f5a6b7c8")))
        .append("_schema", new BsonString("poi"))
        .append("name", new BsonString("Room 1"))

      JsonUtils.mongoDocumentToJson(doc) must equalTo(Json.obj("name" -> "Room 1"))
    }
  }

  "JsonUtils.getHashMapStrStr" should {

    "convert flat JSON values without a Gson round-trip" in {
      val result = JsonUtils.getHashMapStrStr(Json.obj(
        "string" -> "value",
        "number" -> 42,
        "boolean" -> true,
        "null" -> JsNull))

      result.get("string") must equalTo("value")
      result.get("number") must equalTo("42")
      result.get("boolean") must equalTo("true")
      result.containsKey("null") must beTrue
      result.get("null") must beNull
    }
  }
}
