# E-JUST Anyplace — Recovery Test Specification

## Purpose

Anyplace is E-JUST's indoor mapping and navigation system. The recovery target
is a Linux-hosted Scala/Play API with MongoDB, serving existing web and Android
clients. Test only the controlled local or staging system; never target original
Anyplace infrastructure or production data.

## Current testing scope

This TestSprite run validates only completed recovery phases 0–3. Web asset
assembly, floorplan tiling, Android runtime, public-domain/TLS setup, and data
hydration are outside this run.

## API behavior to test

- `GET /api/version` is public and returns HTTP 200 with version information.
- An unknown `GET` route redirects to `/viewer`.
- `POST /api/mapping/space/public` accepts an empty JSON object and returns a
  success response containing `spaces` and `buildings` arrays. An empty staging
  database is valid.
- `POST /api/user/register` accepts valid local user input and rejects missing
  required fields. Registration responses must not reveal plaintext passwords.
- `POST /api/user/login/local` authenticates valid local credentials and rejects
  invalid credentials without exposing sensitive details.
- `POST /api/user/refresh` accepts a valid local access token and rejects a
  missing or invalid token.
- Protected mapping write endpoints reject requests without valid authorization.

## Authentication and data safety

There is no API-key authentication. Public endpoints require no authentication.
For local authentication scenarios, TestSprite must create disposable users in
the controlled staging/test database only. Use unique usernames and email
addresses. Do not use Google sign-in, production accounts, official mapping
data, administrator bootstrap, or external analytics in this run.

## Security expectations

- API responses must not expose credentials, passwords, tokens, or configured
  server secrets.
- External analytics is disabled by default.
- The test server uses a protected application secret and authenticated,
  loopback-only MongoDB in staging.
- Database/listener and systemd security are verified by the Linux staging
  runbook, not through HTTP tests.

## Test execution target

Run against a locally running backend on port `9000`, beginning at
`/api/version`. The backend must have completed the Phase 2 staging runbook
before executing database-backed scenarios.
