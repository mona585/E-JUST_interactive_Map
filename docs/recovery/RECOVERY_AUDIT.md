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

## Phase gate

No Phase 1 recovery work has started. The next phase requires approval after
the operational credential rotation is owned or explicitly accepted as pending.
