# Phase 6 Runbook — Floorplan/Tiler Pipeline

Companion to `docs/recovery/RECOVERY_REPORT.md` Phase 6. Verifies the full
chain end to end, not standalone tiler success:

```
Architect/API upload → MapFloorplanController → MongoDB metadata →
filesystem → tiler → generated tiles/archive → backend retrieval → Viewer display
```

Run on the Ubuntu 22.04 staging host (Phase 1 toolchain, Phase 2 backend,
Phase 4 web assets) with the Phase 5 disposable Campus/Space/Floor fixture
already created.

## 0. Source-side facts this phase relied on (already verified in source)

- The only routed upload action is `uploadWithZoom()`
  (`POST /api/mapping/floor/floorplan/upload`); the deprecated 4-argument
  `upload()`/`tileImage()` path is **not** routed and cannot be reached over
  HTTP. `start-anyplace-tiler.sh` requires exactly 5 positional arguments
  (`imagePath lat lng -DISLOG|-ENLOG zoom`); only `tileImageWithZoom()`
  supplies all five. This is why the 4-argument path is correctly left
  unrouted rather than "fixed" — routing it would still need a zoom value it
  does not have.
- `AnyPlaceTilerHelper.getFloorTilesZipLinkFor` builds links with
  `AnyplaceServerAPI.urlPath("api", "floortiles", buid, floor, zipName)`,
  which joins segments with a literal `/` from the configured
  `public.baseUrl` (R-10). It no longer emits the legacy
  `/anyplace/floortiles` path or OS-dependent `File.separatorChar` in URLs.
  `scripts/Test-FloorplanPipelineContract.ps1` checks this statically.
- `server/anyplace_tiler` is Linux/ImageMagick/AdvanceCOMP-oriented (R-08);
  per D-01 this is accepted, not ported to Windows. Steps 2–5 below cannot
  run on this Windows development host and are **EXTERNAL DEPENDENCY** until
  performed on the pinned Ubuntu 22.04 staging VM from
  `docs/recovery/UBUNTU_22.04_TOOLCHAIN.md`.

## 1. Preflight (Ubuntu staging host)

```bash
./scripts/verify-ubuntu-toolchain.sh   # confirms python3, convert, identify, advpng, zip
```

## 2. Known image fixture

Use one small, clearly-synthetic PNG/JPG (e.g. a solid-color test image with
a few labeled rectangles) — never a real E-JUST floorplan until official data
is approved for hydration (D-02).

## 3. Authenticated upload

Using the Phase 5 bootstrapped Administrator (or an owner/co-owner account)
and the fixture Space/Floor `buid`/`floor_number`:

```bash
curl -s -X POST http://127.0.0.1:9000/api/mapping/floor/floorplan/upload \
  -H "X-Auth: <access_token>" \
  -F "floorplan=@fixture.png" \
  -F 'json={"buid":"<buid>","floor_number":"<floor>","lat_bottom_left":"...","lon_bottom_left":"...","lat_top_right":"...","lon_top_right":"...","zoom":"20"};type=application/json'
```

- Zoom below 18 must be rejected (`RESPONSE.BAD_FLOORPLAN_ZOOM_LEVEL`) —
  confirm this negative case too.
- Expect HTTP 200 "Uploaded floorplan." on success.

## 4. MongoDB metadata

```bash
mongosh "mongodb://127.0.0.1:27017/anyplace" --eval \
  "db.floorplans.findOne({fuid: '<buid>_<floor>'})"
```

Confirm `zoom`, `lat_bottom_left`, `lon_bottom_left`, `lat_top_right`,
`lon_top_right` match the request.

## 5. Filesystem and tiler output

```bash
ls "$FLOORPLANS_ROOT/<buid>/fl_<floor>/"
#   fl_<floor>                     (source image copy)
#   static_tiles/19..22/...        (generated tile tree)
#   static_tiles/bounds.txt
#   static_tiles/tiles_archive.zip
#   anyplace_tiler_fl_<floor>.log  (-DISLOG output)
```

Check the log for a clean `:: Finished Tiling! ::`, and spot-check a couple
of tile image dimensions with `identify`.

## 6. Backend retrieval

```bash
curl -s -X POST "http://127.0.0.1:9000/api/floortiles/<buid>/<floor>" -H "X-Auth: <access_token>"
# -> JSON containing a link built by getFloorTilesZipLinkFor; confirm it is
#    "<public.baseUrl>/api/floortiles/<buid>/<floor>/tiles_archive.zip", not
#    "/anyplace/floortiles/..." and not using backslashes.

curl -s -o tiles_archive.zip "http://127.0.0.1:9000/api/floortiles/<buid>/<floor>/tiles_archive.zip"
unzip -t tiles_archive.zip   # archive integrity
```

## 7. Viewer display

Load the fixture Space/Floor in the Phase-4-built Viewer, confirm the
floorplan overlay renders from the base64/tile data without a 404 or blank
overlay.

## 8. Repeat once more

Definition of Done requires the fixture to pass end to end **twice** from a
clean floorplan directory (delete `$FLOORPLANS_ROOT/<buid>` and repeat steps
3–7) to rule out a one-off artifact from stale state.

## Rollback

Delete only the fixture's MongoDB `floorplans` record and its
`$FLOORPLANS_ROOT/<buid>/fl_<floor>/` directory; this does not touch any
other Space/Floor data.
