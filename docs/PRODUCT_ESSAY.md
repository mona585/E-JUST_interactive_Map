# E-JUST Interactive Map — Product Essay: Intent, Needs, Features, How Built

Author: working notes of the E-JUST deployment engineer, 2026-10-09.
Status: living document. Facts below were verified by execution (builds, tests,
live server runs) unless marked `[doc]` (taken from repository records).

---

## 1. Intent — why this product exists

E-JUST (Egypt-Japan University of Science and Technology) sits on a ~200-acre
smart campus at New Borg El-Arab: faculties (Engineering, BAS, FIBH, CSIT,
PharmD), dormitories, sports zones, food courts, labs, shuttle lines. 4,600+
undergraduates plus postgraduates, many living on campus far from home, must
daily answer one question: **how do I get from this building to that building?**

The intent of this product is a university-owned indoor/outdoor wayfinding
system: a campus map that knows every building, shows where you are, and plots
how to get where you are going — without depending on foreign SaaS, without
leaking student movement data off campus, and maintainable by E-JUST staff
through a mapping tool (Architect) rather than vendor tickets.

It is a fork of the Anyplace indoor-navigation system (University of Cyprus,
IEEE MDM 2020), re-homed to E-JUST: same engine (Play/Scala API + MongoDB +
AngularJS web apps + Android Logger/Navigator), narrowed to the pilot scope
that matters first — **navigation between campus buildings (outdoor)** — with
floor-level indoor routing deferred, not deleted.

Non-goals on purpose: turn-by-turn voice guidance, offline vector maps,
room-level indoor positioning via Wi-Fi fingerprinting (the engine supports it;
the pilot does not need it), public app-store releases (debug APKs first).

---

## 2. Needs — who needs what

| Stakeholder | Need | Priority |
|---|---|---|
| Student / visitor | Open a link, see campus, search a building, get a walking path building→building on a phone | P0 (the product) |
| Campus mapper (staff) | Add buildings/POIs/paths in Architect, publish them, share links | P0 (content pipeline) |
| University IT | Self-host on E-JUST infrastructure, TLS, authenticated DB, backups, no foreign analytics | P0 (sovereignty) |
| Logger field team | Android app pointed at the E-JUST server for fingerprint/POI collection | P1 (mapping input) |
| Future maintainers | Clean seams (service layer, async I/O), tests that pin behavior, seed data, runbooks | P1 (sustainability) |
| Security | Closed write paths, modern password storage, least-privilege tokens, no secret leaks | P0 (launch gate) |

Non-functional needs: campus-burst read performance (hundreds of concurrent
map loads at class-change time), sub-second route responses on seeded data
(measured: Dijkstra over campus graph answers in ms on dev hardware),
HTTPS-only on modern Android, and honest error contracts (IDs, not stack
traces).

---

## 3. Features — needed, status, how made

Legend: ✅ live+proven · 🟡 present but unproven here · 🔴 missing/blocked.

### 3.1 Campus outdoor routing (the core) — ✅ built 2026-10-09

**Need:** tap two places in different buildings, get a path.
**Was:** `POST /api/navigation/route` answered cross-building requests with
`"Navigation between buildings not supported yet."`
**Made:** new vertical — `POST /api/navigation/route/campus`
`{cuid, pois_from, pois_to}` → `{num_of_pois, pois[]}` over the outdoor
connector graph (member Spaces' POIs as vertices, `edge_type:"outdoor"` edges
with both endpoints inside the campus as undirected weighted edges, Dijkstra).
Same response envelope as indoor endpoints so the client reuses its polyline
code. First async endpoint, running on the previously-unused
`blocking-io-dispatcher`. Client: campus viewer branches cross-building taps
to it (same-building keeps indoor), legs keyed `building:floor`, all shown.
Google Directions remains fallback, not foundation — on-campus routing needs
no key, no internet, no billing.
**Proven:** fixture specs + live curl (Engineering→Library = 2 points).

### 3.2 Indoor same-floor / same-building routing — ✅ inherited, kept

Pre-existing Dijkstra over hallway/stair/elevator/room edges (`navigateSameFloor`,
`navigateSameBuilding`). Still serves the last-meter leg (entrance→room).
Unchanged by the campus work; covered by contract specs for its guards.

### 3.3 Campus & Space mapping CRUD — ✅ inherited, hardened around

Campus get/add/update/delete, Space public/get/add/update/delete, POI and
Connection CRUD with space-ownership checks. Surfaced gaps were closed:
floorplan uploads and radiomap deletes/compute now require tokens (were open);
global bbox wipe is admin-only. Untouched: validation depth, pagination.

### 3.4 Floorplan pipeline (tiler) — 🟡 present, deferred

Upload → tile → zip flow exists; heavy, blocking, unaudited at load. Pilot
shows static floorplans; full tiler hardening is roadmap, not launch gate.

### 3.5 Wi-Fi fingerprinting / positioning / heatmaps — 🔴 out of pilot scope

Endpoints exist (`/api/radiomap/*`, `/api/position/*`, `/api/heatmap/*`).
Deliberately unbuilt for the pilot: outdoor navigation does not need them.
They remain served by Play with per-endpoint token gates (writes and deletes
require login; the global wipe additionally requires admin) — scope discipline
is a product decision recorded here, not edge filtering: the Nginx config
proxies `/api/*` wholesale and documents that Play enforces authorization.

### 3.6 Auth & accounts — 🟡 rebuilt, migration-safe

Local register/login/refresh, Google login, roles (first user admin). Rebuilt:
PBKDF2-SHA256 (210k rounds, per-user salt) for new passwords with
bug-compatible legacy-SHA verification so existing accounts keep working
(the legacy hex routine drops nibbles — "fixing" it would lock everyone out;
noted in code), `SecureRandom` tokens, password-material logging removed,
login rewritten to fetch-by-username + verify (per-user salts can't be query
keys). Still weak by choice-deferred: no token expiry, Google `aud` unchecked.

### 3.7 Campus viewer web app — 🟡 working, key-blocked

AngularJS campus viewer serves (200s across index/bundle/css/images, seeded
markers resolve). Fixed: portable share URLs (`location.origin`), dead URL
shortener removed (Google killed it 2019), Flurry tracker removed, campus
route wired. Blocked visibly: `__MAPS_API_KEY__` placeholder — base map tiles
need the host key. Local bundles are concat-built (no minification); host
builds minified via Grunt.

### 3.8 Architect web app — 🟡 serving, interceptor extended

Serves (99 KB index). Token interceptor extended to the newly-gated mutating
URLs (it previously covered `/api/auth/*` only — verified before gating, or
the gate would have broken Architect).

### 3.9 Android Logger / Navigator — 🔴 unbuilt here

Fail-closed `BuildConfig` (`PUBLIC_BASE_URL` required), properties-driven
release signing — both correct. Blocked: `clients/core/lib` submodule
uninitialized (SSH-only) and no SDK on this box. Host task with deploy key.

### 3.10 Operations — 🟡 shaped, uninstalled

`anyplace.service` (unit shape correct for `/opt/anyplace`), production Nginx
config written (unparsed — no nginx here; host `nginx -t` is the proof),
`init_schema.js` indexes, `init_database.sh`, `backup.sh` present but unscheduled,
`/api/health` liveness added, demo seed (`seed_demo_campus.js`, idempotent,
executed). Missing on host: Mongo+auth install, TLS, timers, monitoring,
real campus data.

---

## 4. Architecture as-built (2026-10-09)

```
Browser / Android
      │  HTTPS (host Nginx: /api/*, /floortiles/*, /architect/*, /viewer/*)
      ▼
Play 2.8 / Scala 2.13 (:9000 loopback)
 ├── Controllers (thin-ish; NavigationController owns one service + one dispatcher)
 ├── services/CampusNavigationService  ← the pattern to replicate
 ├── ProxyDataSource → MongodbDatasource (blocking; 10s timeouts; pool 40/5)
 └── MongoDB 6.x (loopback, auth, 2dsphere + id indexes)
```

Request flow (campus route): client → Nginx → `getCampusRoute` (async,
blocking-io-dispatcher) → resolve POIs → campus buids → POI maps + outdoor
edges → Dijkstra → `NavResultPoint[]` → `{num_of_pois, pois}` → red polylines
keyed `buid:floor`.

## 5. Data model (pilot-relevant)

Campus `{cuid, name, description, greeklish, buids[]}` → Spaces `{buid, …,
is_published}` (public listing **requires** `"true"` — discovered by execution,
documented in seed) → POIs `{puid, buid, floor_number, coordinates_lat/lon
(strings), pois_type, is_building_entrance}` → Edges `{pois_a/b, buid_a/b,
floor_a/b, edge_type: hallway|room|stair|elevator|outdoor, weight}`. Campus
routing reads outdoor edges only; indoor routing reads the rest.

## 6. Security posture (blunt)

Closed this week: open uploads/deletes, password logging, weak tokens,
verbose errors, trackable share URLs, third-party tracker, 6 binaries in git.
Still open: token expiry, Google `aud`, rate limiting (planned as Nginx
`limit_req`), salt/pepper rotation procedure, CSRF semantics review.
**Closed staging: yes. Public: after the remaining list.**

## 7. Deployment story

Dev box builds + proves (Java 11 stand-in, throwaway loopback Mongo,
concat-built web). Host provisions (Ubuntu 22.04, JDK 17, auth Mongo, Node 22
web build, Maps key, certbot, timers) and runs the same 5-curl acceptance plus
the seeded demo walk. Docker `docker/` stays retired (own README says
deprecated; it ships Couchbase + a 4.0 binary for Ubuntu 18.04).

## 8. What "clean product" still requires (roadmap, ordered)

1. Service-layer rollout per controller + async migration (campus pattern).
2. Token expiry/rotation + Google `aud` + rate limits + backup/monitoring timers.
3. Real E-JUST mapping (campus, buildings, entrances, outdoor paths) via Architect.
4. Android submodule + SDK + debug APKs → signed release custody.
5. Tiler hardening or managed replacement; fingerprinting only if indoor scope returns.
6. Frontend: campus-first defaults, loading/empty states, key management.

*Companion: `CODE_REVIEW_FAILURE_AUDIT.md` — the adversarial review.*
