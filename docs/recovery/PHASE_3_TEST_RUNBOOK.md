# Phase 3 Test Runbook

Run these checks only on the controlled Ubuntu staging VM after the Phase 2
runbook succeeds. Mongo-backed tests are an explicit opt-in and must never
target an official production dataset.

Verified on the staging VM on 2026-08-22: default suite 5 passed / 1 skipped,
opt-in suite 18/18, disposable-database isolation confirmed.

## Runtime requirements (verified 2026-08-22)

The suite constructs the full Guice application for every `WithApplication`
test, so two things are mandatory even for the default suite:

1. **Environment substitutions.** `app.private.conf` resolves
   `${MONGODB_*}` and `${PUBLIC_BASE_URL}` from process environment variables.
   Export a *disposable database* set before running so tests never touch the
   main database:

   ```bash
   export PUBLIC_BASE_URL=http://127.0.0.1:9000
   export MONGODB_HOST=127.0.0.1 MONGODB_PORT=27017
   export MONGODB_DATABASE=anyplace_test
   export MONGODB_USERNAME=<test-user> MONGODB_PASSWORD=<test-user-password>
   ```

2. **Java module flags.** The test JVM needs the same flags as production or
   Guice/cglib fails with `InaccessibleObjectException` (the R-03 signature):

   ```bash
   export JDK_JAVA_OPTIONS="--add-opens=java.base/java.lang=ALL-UNNAMED \
     --add-opens=java.base/java.util=ALL-UNNAMED \
     --add-opens=java.base/java.lang.invoke=ALL-UNNAMED \
     --add-opens=java.base/java.io=ALL-UNNAMED"
   ```

3. If credentials are sourced from `/etc/anyplace/`, that directory needs mode
   0711 so the service account can traverse it.

## Default backend suite

From `/opt/anyplace/server` as the `anyplace` service account:

```bash
./sbt test
```

Expected result: the Viewer redirect, unauthenticated version, public spaces,
unauthorized-endpoint, and public-URL-construction tests pass; the Mongo-gated
`SecurityRegressionSpec` reports one skipped example.

Note: despite earlier wording, the default suite does construct the
application and therefore reaches MongoDB through the eager startup binding;
keep the substituted values pointed at the disposable database.

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

On this branch the spec gates only on `RUN_MONGO_INTEGRATION_TESTS=true`; the
database actually written is the one selected by the `MONGODB_*` environment
above. Expected result: all 18 examples pass. The test database may contain
disposable users only; remove or recreate it after the run. Google login is
intentionally outside this launch baseline.

## TestSprite

TestSprite was not initialized in this repository because its bootstrap can
tunnel a local API and expose private repository context to a third party. Use
it only after the repository owner explicitly approves that exposure (recorded
in RECOVERY_AUDIT.md), and point it only at the controlled staging backend.
Until the CLI is initialized, TC001 and TC002 are executed as direct probes:
`GET /api/version` must return HTTP 200 version JSON and an unknown GET route
must return HTTP 303 redirecting to Viewer.
