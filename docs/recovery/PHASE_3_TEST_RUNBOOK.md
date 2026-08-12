# Phase 3 Test Runbook

Run these checks only on the controlled Ubuntu staging VM after the Phase 2
runbook succeeds. The default suite tests public routes without requiring
MongoDB; Mongo-backed tests are an explicit opt-in and must never target an
official production dataset.

## Default backend suite

From `/opt/anyplace/server` as the `anyplace` service account:

```bash
./sbt test
```

Expected result: the Viewer redirect and unauthenticated `/api/version` tests
pass. Mongo-backed security tests are skipped unless explicitly enabled.

## Controlled Mongo-backed tests

Create a disposable `anyplace_test` database and a restricted user with access
only to that database. Export its values in the same private shell; do not add
them to a repository file:

```bash
export RUN_MONGO_INTEGRATION_TESTS=true
export MONGODB_TEST_HOST=127.0.0.1
export MONGODB_TEST_PORT=27017
export MONGODB_TEST_DATABASE=anyplace_test
export MONGODB_TEST_USERNAME=<test-user>
export MONGODB_TEST_PASSWORD=<test-user-password>
./sbt test
```

The test database may contain disposable users only. Remove or recreate it
after the run. Google login is intentionally outside this launch baseline.

## TestSprite

TestSprite was not initialized in this repository because its bootstrap can
tunnel a local API and expose private repository context to a third party. Use
it only after the repository owner explicitly approves that exposure, and point
it only at the controlled staging backend.
