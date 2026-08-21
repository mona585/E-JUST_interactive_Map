# Implementation Plan — CampusFind (anyplace_campusfind)

## Overview
Fix the root causes of "changing API/server does not change displayed data" and prepare the app for Google Maps integration with backend isolation.

## Current Root Causes (Why API changes seem ineffective)
1. **Campus selection never wired** — RootRouter→MainShell never shows campus picker; data loads from `/api/mapping/space/public` (ALL buildings globally) regardless of server URL.
2. **api_config.dart defaults to wrong server** — Default `https://anyplace.cs.ucy.ac.cy` overrides `.env.example` if `--dart-define=SERVER_URL` not passed.
3. **Stale offline snapshot** — `CacheService.loadOfflineSnapshot()` restores from `campus_data_snapshot.json` when live fetch fails, showing old data.
4. **Search index built from cached data** — Not refreshed until cache cleared.
5. **Tile cache persists old floorplans** — Not invalidated on campus change.

## Phase 1: Fix Campus Selection Wiring + Correct API Base URL
- **Goal**: Ensure app shows data scoped to the selected campus, and the backend URL is correct.
- **Files/Classes Involved**: 
  - `lib/main.dart` (RootRouter)
  - `lib/screens/campus_selection_screen.dart`
  - `lib/providers/providers.dart`
  - `lib/config/api_config.dart`
  - `lib/providers/bulk_load_provider.dart`
  - `lib/services/cache_service.dart`
  - `lib/config/constants.dart`
- **What Will Change**:
  1. `RootRouter` → show `CampusSelectionScreen` on first launch (when no selected campus id in SharedPreferences).
  2. `CampusSelectionScreen.onSelected` → persist campus id via `CacheService.setSelectedCampusId` + `selectedCampusIdProvider`.
  3. `MainShell` → gate all data loading on selected campus id; when null, show error/retry instead of loading global data.
  4. `api_config.dart` → change default `SERVER_URL` from `https://anyplace.cs.ucy.ac.cy` to `http://anyplace.ejust.edu.eg:443`.
  5. `BulkLoader._loadScopedDataset` → when campus id selected, fetch via `/api/mapping/campus/get` scoped to that campus; without campus, show error (no more global fallback).
  6. Clear stale offline snapshot when campus changes (`CacheService.clearData()`).
- **Dependencies Between Phases**: Phase 1 must complete before Google Maps integration (campus scoping is prerequisite for meaningful map data).
- **Verification**:
  - Build with `--dart-define=SERVER_URL=http://anyplace.ejust.edu.eg:443` and verify building count matches expected E-JUST dataset.
  - Launch app, complete campus selection, verify only E-JUST buildings appear.
  - Switch SERVER_URL dart-define to wrong URL → verify error/empty state (not silent wrong data).
  - Clear cache, re-launch → data refreshes from new server.
- **Must NOT Change**: Backend API contracts (`api.json`), model schemas, existing UI layouts, offline snapshot format, Riverpod provider structure.

---

**PLAN COMPLETE. NOW EXECUTING PHASE 1.**