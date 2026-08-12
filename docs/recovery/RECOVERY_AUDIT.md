# Recovery Audit

## Audit basis

Phase 0 was audited against `EJUST_RECOVERY_AUDIT_INSTRUCTIONS_V2.md` and
the current checkout, not against completion claims alone. The checkout is on
`master` at `1cf45299`; `PHASES_COMPLETED.md` instead cites `main` and commits
that are not present in the local object database. Its earlier Phase 0 claim is
therefore **NOT VERIFIED**. The instruction's reference to
`docs/recovery/PHASES_COMPLETED.md` also does not match the supplied root file.

## Phase 0 — Security containment

**Status: PARTIAL — source containment is verified; credential rotation is an
external operational dependency.**

### Verified and repaired

- Replaced the literal Play/application secret in `anyplace.service` with the
  required protected file `/etc/anyplace/anyplace.env` and
  `${APPLICATION_SECRET}`.
- Made `install.sh` create that file with directory mode `0700` and file mode
  `0600`; it no longer prints application secrets, salts, peppers, or MongoDB
  passwords. Existing secret, salt, and pepper values are preserved rather than
  silently regenerated.
- Removed insecure fallback defaults from `start.sh` and the installer. Startup
  now fails when the secret is absent or still a documented placeholder.
- Replaced exposed Google Maps/Directions/URL-shortener keys in active and
  legacy clients with explicit placeholders, and added environment-file ignores.
  The tracked legacy iOS bundle was changed alongside its source solely to
  eliminate the exposed credential; regenerate it before any future legacy build.
- Stopped backend authentication endpoints and the Architect client from logging
  request bodies or access tokens.

### Validation evidence

- `powershell -NoProfile -ExecutionPolicy Bypass -File
  scripts/Test-SecretContainment.ps1` — passed. This repeatable check rejects
  known exposed-key/default-secret patterns and verifies the service, installer,
  and authentication logging safeguards.
- Git Bash `bash -n install.sh` and `bash -n start.sh` — passed.
- `git diff --check` — passed.
- `server/./sbt test` — **not verified**. The first run was blocked by a
  protected Windows Coursier cache. A retry using a repository-local cache
  downloaded SBT but did not finish before the 64-second execution limit. No
  test result is claimed.

TestSprite was not used in this phase because the acceptance criteria are static
source/configuration containment rather than a backend HTTP contract. It should
be used from the first API/integration phase where it adds coverage.

### Required operational follow-up

Treat every removed credential as exposed: revoke/rotate the Google keys and
the prior Play/application secret in the credential-owning console and any
running Linux host, then install the new secret in
`/etc/anyplace/anyplace.env` before service restart. Coordinate any history
rewrite only after rotation; it is not part of this phase.

## Phase 1 — Pin the Linux/Ubuntu toolchains

**Status: PARTIAL — the source-side contract is verified; a clean Ubuntu VM
execution is an external dependency.**

### Audit result and repair

The earlier Phase 1 claim is **NOT VERIFIED**: it cites an absent execution log
and no accessible Ubuntu VM/image. The actual checkout also conflicted with the
claim: `.sdkmanrc` selected Java 7, and `install.sh`/`start.sh` preferred Java
11 when both 11 and 17 were installed. The root guide still allowed Ubuntu
20.04 and unpinned tooling.

The recovery target is now documented in
`docs/recovery/UBUNTU_22.04_TOOLCHAIN.md`: Ubuntu Server 22.04 LTS, OpenJDK 17,
SBT 1.5.8, Scala 2.13.6, Play 2.8.8, Node 22/npm 10, Grunt CLI 1.5.0, Bower
1.8.14, MongoDB 6.0.x tools, and the Python/ImageMagick/AdvanceCOMP tiler
requirements. `scripts/verify-ubuntu-toolchain.sh` makes the contract
checkable on the target VM. The SDKMAN selector, runtime scripts, and systemd
template now consistently choose JDK 17. The root guide marks the unpinned
legacy installer as investigation-only.

### Validation evidence

- `powershell -NoProfile -ExecutionPolicy Bypass -File
  scripts/Test-ToolchainContract.ps1` — passed.
- Git Bash `bash -n install.sh`, `bash -n start.sh`, and
  `bash -n scripts/verify-ubuntu-toolchain.sh` — passed.
- `git diff --check` — passed.
- Clean Ubuntu compile, MongoDB preflight, tiler run, web `npm ci`/Bower build,
  and Android SDK build — **not run**. This Windows host is intentionally not
  the target production environment.

### External dependency

`clients/android-new/lib-android` and `clients/core/lib` are uninitialized Git
submodules in this checkout. They use SSH remotes and require authorized access
before Navigator/Logger can be built in Phase 7. Do not replace them with a
different library source.

## Phase gate

No Phase 2 recovery work has started. Approve Phase 2 when an Ubuntu 22.04 VM
or staging host is available for the documented preflight and MongoDB can be
configured locally with authentication.

## Phase 2 — Backend startup and MongoDB connectivity

**Status: PARTIAL — the source-side startup contract is verified; the required
Ubuntu VM runtime validation is an external dependency.**

### Audit result and repair

The earlier Phase 2 completion claim is **NOT VERIFIED**. No local private
configuration, staging host, or execution evidence exists in this checkout.
The source itself contradicted the desired D-06 baseline: `start.sh` and the
installer could create a Docker MongoDB instance with `-p 27017:27017`, which
publishes the port on all interfaces; the configuration template allowed a
blank database password; and `anyplace.service` used a personal account and
absolute workstation path.

The canonical service now runs as the dedicated `anyplace` account from
`/opt/anyplace`, reads `/etc/anyplace/anyplace.env`, and logs to `journald`.
The environment contract requires application and `MONGODB_*` values; the
private HOCON configuration resolves them without tracking credentials.
`start.sh` now fails before launch unless the database host is loopback, all
credentials are present, and the local port is reachable. The installer no
longer starts or publishes MongoDB through Docker and no longer blanks
database credentials. `PHASE_2_STAGING_RUNBOOK.md` records the required
authenticated MongoDB provisioning, service installation, API probe, and
restart test.

External analytics remains disabled by default in `Anyplace.scala` and the
private configuration template; no analytics-enabling change was made.

### Validation evidence

- `powershell -NoProfile -ExecutionPolicy Bypass -File
  scripts/Test-StartupContract.ps1` — passed.
- `powershell -NoProfile -ExecutionPolicy Bypass -File
  scripts/Test-SecretContainment.ps1` — passed.
- Git Bash `bash -n install.sh` and `bash -n start.sh` — passed.
- `git diff --check` — passed.
- Two clean service starts/stops, authenticated MongoDB app read probe,
  loopback listener inspection, `/api/version`, and log/network checks —
  **not run** because no controlled Ubuntu staging VM is available.

TestSprite was not used: no controlled local/staging backend is available to
target safely. It becomes appropriate in Phase 3 after the Phase 2 runbook
has produced a running private endpoint.

## Phase gate

No Phase 3 recovery work has started. Approve Phase 3 after the Phase 2
staging runbook has been executed, or explicitly approve source-only test
baseline work while the VM validation remains pending.
