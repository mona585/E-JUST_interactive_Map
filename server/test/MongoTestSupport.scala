/**
 * Mongo-backed integration tests require a controlled database, credentials,
 * and a running MongoDB instance. They are opt-in so the default unit-test
 * suite remains deterministic on developer workstations and clean CI runners.
 *
 * CI/staging must set RUN_MONGO_INTEGRATION_TESTS=true and the MONGODB_TEST_*
 * variables documented in server/test/resources/application.conf.
 */
object MongoTestSupport {
  val enabled: Boolean =
    sys.env.get("RUN_MONGO_INTEGRATION_TESTS").exists(_.equalsIgnoreCase("true"))

  val skipMessage: String =
    "SKIPPED: Set RUN_MONGO_INTEGRATION_TESTS=true and MONGODB_TEST_* to run Mongo-backed integration tests."
}
