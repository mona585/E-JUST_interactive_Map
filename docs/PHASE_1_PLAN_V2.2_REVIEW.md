# PHASE 1 PLAN V2.2 — Outdoor-Only CampusFind Sibling Application

> **IMMUTABLE REVIEW BASELINE: This plan is a read-only reference. It must NOT be edited, regenerated, renamed, or overwritten during implementation or planning. Any future plan change requires a separately named, explicitly approved revision.**

**Revision identifier:** V2.2
**Supersedes (for implementation only after explicit user approval):** `docs/PHASE_1_PLAN_V2.2_REVIEW.md` is the **implementation-authoritative** plan **only once the user explicitly approves it**. Until that approval, **no** plan file is authoritative.
**Historical preservation:** `docs/PHASE_1_PLAN_V2.1_REVIEW.md` **remains immutable and preserved** for historical comparison. Verified at write time — SHA-256 `D623817FBF2FF5030A23E3C9BE802B54FFA6D5C788AFDFE2F046D5561940C384`, size 51017 bytes. **Do not delete, rename, or modify it.**
**Source of truth used to draft this revision:** V2.1 (read in full).
**Scope:** Planning + verification only. **Source:** `clients/flutter/anyplace_campusfind` · **Target:** `clients/flutter/campusfind_outdoor`
**Change markers:** `[V2.2 CHANGE]` = corrected relative to V2.1 · `[V2.2 ADDITION]` = new in V2.2 · `[CARRY]` = retained verbatim-in-substance from V2.1.
**Evidence labels:** **CONFIRMED** (read-only inspected) · **REPORTED** (prior finding, CP-0 must verify) · **HYPOTHESIS** (code-level claim not yet directly verified; CP-0 must verify) · **UNRESOLVED**.

### How to read this document
* No command output in this document is invented. Commands/scripts are **proposed** unless explicitly labelled as already executed.
* Every code-level claim carried from V2.1 that was not itself read-verified is labelled **HYPOTHESIS** and deferred to CP-0.
* This revision does **not** claim user approval or implementation authorization.
* Per-task restriction: this planning task creates/modifies **only** `docs/PHASE_1_PLAN_V2.2_REVIEW.md`. No script, changelog, helper, report, or other artifact is created. All scripts live inside this document.

---

## 0. V2.2 Revision History and Change Summary

| Correction | What changed in V2.2 | Where |
|---|---|---|
| **A — Byte-safe Gate B** | V2.1 stored and read NUL-delimited `git status -z` output with text cmdlets (`Set-Content`/`Get-Content`), which can corrupt NUL bytes, and treated each token as an independent status line, which mishandles rename/copy records. V2.2 replaces this with a **byte-exact process capture** (raw stdout bytes, no PowerShell text pipeline), a **structured porcelain v1 `-z` parser** that consumes both paths of `R`/`C` records, a **structured (not lossy text) comparison**, fail-closed error handling, and a mandatory **positive/negative self-test suite**. | §4.3–§4.8 |
| **B — Authorization & sequencing** | Added an explicit, unambiguous sequence that distinguishes **technical verification**, **plan acceptance**, and **implementation authorization**, and forbids automatic checkpoint continuation. | §8.0, §12.3 |
| **C — Exact-path allowlists** | All checkpoint file-authorization rules now require an **exact repository-relative path list** established by repo inspection and user-approved before editing; broad directories/globs/categories are explicitly insufficient. Gate B's documentation exception is an **exact two-path list**; the implementation-authoritative plan is defined **only after user approval**; implementation may modify neither plan artifact; filename-pattern authorization is forbidden. | §8, §9.4, §9.5 |

`[CARRY]` All other V2.1 content (goals, scope, isolation, identity/channel, manifests M1/M2/M3, classification, MVVM, test inventory, checkpoints CP-0…CP-10 incl. CP-7A/CP-7B, gates A/A′/A″/B, R1–R12, U1–U10, A1–A7, stop conditions, acceptance criteria) is retained. A section-by-section cross-check against V2.1 is recorded in §13.

`[V2.2 ADDITION]` V2.1's 46-vs-47 test-count fact and the pre-existing baseline facts are carried as **CONFIRMED (V2.1 planning pass)** but must still be **re-captured at CP-0**.

---

## 1. Objective, Scope, Definition of Done

### 1.1 Objective `[CARRY]`
Create `clients/flutter/campusfind_outdoor` as an **Outdoor-only, strict-MVVM** sibling of `clients/flutter/anyplace_campusfind`, preserving the source's Outdoor behavior, campus data, routing/rerouting semantics, and the user's pre-existing working-tree state — **without modifying the source app**. This document authorizes **nothing**; implementation requires a separate explicit user message.

### 1.2 In scope (Phase 1) `[CARRY]`
Sibling creation · Android/package/brand identity · heading-channel rename · Indoor runtime removal · MVVM responsibility extraction · test classification/migration · integrity + acceptance verification.

`[V2.2 ADDITION]` Explicitly preserve, subject to CP-0 verification: Google hybrid basemap behavior · overlays · building markers/list · Services quick access · outdoor routing · and **any existing user-added-building capability**. If such a capability does not currently exist, **do not invent one** — record the finding and preserve whatever building-data behavior actually exists.

### 1.3 Out of scope `[CARRY]`
Toolchain upgrades · algorithm redesign · server/backend/web/android-new changes · restoring pre-existing deletions · Phase 2+ work · any behavior change not separately approved.

### 1.4 Definition of Done

| # | Criterion | Evidence source | Status now |
|---|---|---|---|
| D1 | Target exists and is a runnable Flutter app | `flutter analyze` + `flutter test` from target dir | Not executed |
| D2 | Source tree byte-identical to CP-0 full manifest | Gate A″ | Not executed |
| D3 | Pre-existing working tree preserved; only exact-path-allowlisted new paths | Gate B (§4) | Not executed |
| D4 | No reachable Indoor runtime dependency in target runtime graph | §6.4 dependency map + regressions | Partial (F1–F6) |
| D5 | Outdoor routing/rerouting/gate/KMZ behavior preserved | targeted regressions + asset-graph tests | Not executed |
| D6 | Strict MVVM responsibility checks pass | §6.3 assertions | Not executed |
| D7 | Identity confirmed: `eg.edu.ejust.campusfind_outdoor`, label `CampusFind Outdoor`, channel renamed atomically | manifest/gradle/source inspection | Not executed |
| D8 | No source secret copied; key never printed | presence/absence check + hash-only audit | Not executed |
| D9 | Test inventory reconciled and classified | §7 | **CONFIRMED (V2.1 planning pass)** inventory; classification pending |
| D10 | Every outdoor behavior change approved in writing | approval record | Not obtained |
| D11 `[V2.2 ADDITION]` | Every checkpoint edited only its exact-path allowlist; no unauthorized path changed | per-checkpoint allowlist diff | Not executed |

---

## 2. Source/Target Isolation `[CARRY]`

* **Source** `clients/flutter/anyplace_campusfind` is the reference and is **read-only** for the entire implementation.
* **Target** `clients/flutter/campusfind_outdoor` is the only implementation surface.
* **CONFIRMED (V2.1 planning pass):** target does not currently exist. (Re-verify at CP-0.)
* No Phase 1 action may touch `server/`, `clients/web/`, `clients/android-new/`, `clients/android/`, `clients/deprecated/`, or the stale root Flutter app (`lib/{core,data,state,ui}/`).
* `AGENTS.md` (repo root) is a **pre-existing user change** and must not be modified further.
* **The two immutable review artifacts `docs/PHASE_1_PLAN_V2.1_REVIEW.md` and `docs/PHASE_1_PLAN_V2.2_REVIEW.md` are never implementation targets** (§9.5).

---

## 3. Copy Contract, Identity, Secrets, Manifests

### 3.1 `[CARRY]` Copy method — proposal, not executed
A Git-only copy is disqualified: the source contains untracked build-critical files (wrapper JAR + scripts). Use a filesystem copy.

**PROPOSAL:**
```powershell
$src = "clients\flutter\anyplace_campusfind"
$dst = "clients\flutter\campusfind_outdoor"

robocopy $src $dst /E `
  /XD .dart_tool build .gradle .kotlin .idea .vscode `
  /XF local.properties .flutter-plugins-dependencies `
      GeneratedPluginRegistrant.java `
  /NFL /NDL /NJH /NP
$rc = $LASTEXITCODE                 # capture IMMEDIATELY, before any other command
if ($rc -ge 8) { throw "robocopy failed: $rc" }
```

**CP-0 must validate via a non-writing dry run before authorization:**
```powershell
robocopy $src $dst /E /L `
  /XD .dart_tool build .gradle .kotlin .idea .vscode `
  /XF local.properties .flutter-plugins-dependencies GeneratedPluginRegistrant.java `
  /NFL /NDL /NJH /NP /FP /NS
```
Validation obligations:
1. Listing **includes** `android/gradlew`, `android/gradlew.bat`, `android/gradle/wrapper/gradle-wrapper.jar`.
2. Listing **excludes** `android/local.properties`, `.flutter-plugins-dependencies`, `GeneratedPluginRegistrant.java`.
3. Hidden files not explicitly excluded are included (robocopy includes hidden files by default; if any hidden file is skipped, change the method).
4. `/XD build` matches only generated output, not a legitimate source dir named `build`.
5. `.dart_tool` exclusion does not drop anything required by `flutter pub get`.
6. The implementation agent must validate the copy rule against actual repo state — no assumption.

**Fail → STOP; do not copy.**

### 3.2 `[CARRY]` Exclusion policy (identical on both sides of every excluded comparison)

| Excluded item | Kind | Purpose | In full-source manifest? |
|---|---|---|---|
| `.dart_tool/` | generated | regenerated by `pub get` | **Yes** |
| `build/` | generated | build output | **Yes** |
| `android/.gradle/` | generated | Gradle cache | **Yes** |
| `android/.kotlin/` | generated | Kotlin cache | **Yes** |
| `.idea/`, `.vscode/` | editor local | not app content | **Yes** |
| `android/local.properties` | **secret + machine-local** | `MAPS_API_KEY`, `sdk.dir`, `flutter.sdk` | **Yes (hashed only)** |
| `.flutter-plugins-dependencies` | generated | regenerated | **Yes** |
| `GeneratedPluginRegistrant.java` | generated | regenerated; never hand-edit | **Yes** |

Rule: an exclusion from a **copy** never implies exclusion from the **source-integrity** manifest.

### 3.3 `[CARRY]` Identity changes (Phase 1, minimal)

| Item | Source | Target | Note |
|---|---|---|---|
| Dart package (`pubspec.yaml` `name:`) | `anyplace_campusfind` | **unchanged** | avoids Dart import rewrites |
| Android `namespace` | `eg.edu.ejust.anyplace_campusfind` | `eg.edu.ejust.campusfind_outdoor` | verify current value at CP-0 |
| `applicationId` | `eg.edu.ejust.anyplace_campusfind` | `eg.edu.ejust.campusfind_outdoor` | |
| Kotlin package decls | `eg.edu.ejust.anyplace_campusfind` | `eg.edu.ejust.campusfind_outdoor` | atomic with the above |
| App label | (current) | `CampusFind Outdoor` | verify current label at CP-0 |
| Heading channel | `eg.edu.ejust.anyplace_campusfind/heading_stream` | `eg.edu.ejust.campusfind_outdoor/heading_stream` | **atomic**: Dart + Kotlin, one checkpoint |

**No toolchain upgrade** in Phase 1 without separate approval.

### 3.4 `[CARRY]` Manifest lifecycle — three distinct manifests

**Output root (outside the repo):** `$audit = Join-Path $env:TEMP "campusfind_v2_2_audit"`.
**Relative-path normalization:** paths relative to the manifest root, separators normalized to `/`, trailing slashes stripped.
**Sorting:** ascending ordinal by normalized path, before writing and before comparison.
**Hash algorithm:** SHA-256.
**Guarantee scope (explicit):** the manifest guarantees **file path + file content identity only**. It does **not** cover empty directories, file modification times, ACLs, alternate data streams, or git-ignore semantics. No broader guarantee may be claimed.
**Secret safety:** only hashes are emitted; file contents are never printed.

| # | Manifest | Root | Exclusions | Captured at | Compared at | Failure behavior |
|---|---|---|---|---|---|---|
| M1 | Full source integrity baseline | `clients/flutter/anyplace_campusfind` | **none** | CP-0 | CP-10 (Gate A″) | any diff → **STOP**, do not auto-repair |
| M2 | Copy-equivalence (source side + target side) | source & target app roots | §3.2 list, **identical both sides** | CP-1 | CP-1 (Gate A) | any unmatched diff → **STOP** |
| M3 | Post-identity / per-checkpoint target manifests | target app root | per-checkpoint **exact-path** allowlist (§9.4) | each authorized checkpoint | corresponding checkpoint (Gate A′) | any diff not matching exactly one allowlisted path → **STOP** |

M2 proves only that *included* files match; it is **not** proof of source integrity (that is M1/Gate A″).

`[V2.2 ADDITION]` **Distinctness rule:** a successful hash check of a plan file is **not** proof that the source app is unchanged. Source integrity (M1/Gate A″), copy equivalence (M2/Gate A), and target checkpoint integrity (M3/Gate A′) are three independent checks; passing one never implies another.

---

## 4. Pre-existing Git-Worktree Protection and Gate B (Correction A — byte-safe)

### 4.1 `[CARRY]` Why status letters are insufficient
An already-modified file (` M`) keeps the same status letter even if its content changes again. A deletion entry disappears only if the file is restored. Gate B must therefore compare **paths + statuses + content hashes**, not status letters alone.

### 4.2 `[CARRY]` Baseline — CONFIRMED (V2.1 planning pass, read-only)
```
branch : navigation-app
HEAD   : 534ff9086d5e3296dfc7daa2e314726c1e973b25
```
Porcelain (`--porcelain=v1 -uall`), 13 entries:
```
 M AGENTS.md
 D CONTEXT.md
 D CONTRIBUTING.md
 D FINAL-AUDIT.md
 D FINAL-CAMPUSFIND-REPORT.md
 D IMPLEMENTATION-REPORT.md
 D IMPLEMENTATION_PLAN.md
 D MASTER-PLAN.md
 D REBUILD-PLAN.md
 D RECOVERY_REPORT.md
 D changes/CHANGE-001-outdoor-route-domain-placement.md
 D changes/CHANGE-002-navigation-value-objects-in-domain.md
 D plans/smart-marinating-fog.md
```
Pre-existing modified-file content hash (**CONFIRMED (V2.1 planning pass)**):
```
AGENTS.md  SHA-256 = B0EAC4E1B58D33A1A00BCC43E510C2CFAC535445AE7C651690B3614F563786E7
```
The two immutable plan artifacts are pre-existing untracked (`??`) entries.
`[V2.2 CHANGE]` These facts and hashes must be **re-captured by the implementation agent at CP-0**; the values above are a planning-pass observation and are **not** a substitute for CP-0 capture. The implementation baseline is captured at CP-0, **before** any implementation.

### 4.3 `[V2.2 CHANGE]` Gate B requirements (byte-safe)

1. Capture at CP-0, byte-exact: branch, HEAD, the raw `git status --porcelain=v1 -uall -z` byte stream, and per-file SHA-256 for every pre-existing `M`/`??` entry.
2. Record the exact 12 pre-existing deleted paths and verify they remain deleted (absent on disk).
3. Permitted new/changed paths are **only an exact allowlist** — see §4.6 and §9.5. This is **not** a directory wildcard.
4. Compare **structured records** (XY + path [+ original path for renames]) and **content hashes** — never a lossy text conversion of the status stream.
5. Distinguish **pre-existing** status from **implementation-introduced** status (a path present in the baseline is pre-existing; a path absent from the baseline is implementation-owned and must be on the exact allowlist).
6. **Fail closed:** malformed output, ambiguous record, parse failure, unexpected status transition, undecodable path, or unclassified path → **STOP the checkpoint**.
7. Do **not** stage, reset, restore, stash, clean, or rewrite any file as part of the comparison.
8. Run the mandatory self-tests (§4.7) any time the parser or comparator is used; a parser that has not passed its self-tests in the current environment must not be used for a pass/fail decision.

### 4.4 `[V2.2 CHANGE]` Byte-exact capture specification

**Goal:** obtain `git status --porcelain=v1 -uall -z` output **without** passing it through any PowerShell text cmdlet that can re-encode or strip NUL bytes.

**Why V2.1's approach was wrong:** `Set-Content`/`Get-Content` operate on decoded strings; NUL bytes are not reliably preserved, and the `-z` stream is a sequence of NUL-terminated records, not lines.

**Specification (PowerShell 5.1, proposed — CP-0 must verify availability):**
```powershell
# Capture raw stdout bytes via .NET process redirection (bypasses PS text pipeline).
function Get-GitStatusRawBytes {
  param([Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$OutFile)
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName               = 'git'
  $psi.Arguments              = "-C `"$Repo`" status --porcelain=v1 -uall -z"
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError  = $true
  $psi.UseShellExecute        = $false
  $proc = [System.Diagnostics.Process]::Start($psi)
  $ms = New-Object System.IO.MemoryStream
  $proc.StandardOutput.BaseStream.CopyTo($ms)   # RAW bytes; no decoder
  $err = $proc.StandardError.ReadToEnd()
  $proc.WaitForExit()
  if ($proc.ExitCode -ne 0) { throw "git status failed ($($proc.ExitCode)): $err" }
  [System.IO.File]::WriteAllBytes($OutFile, $ms.ToArray())
}
```
Notes / limitations (must be documented and respected):
* `.BaseStream` is read directly to avoid the StreamReader decoder — this is the byte-exact path.
* The output file is written with `WriteAllBytes` (no encoding, no BOM).
* **Alternative runtime:** if CP-0 verifies Python (or another byte-safe runtime) is available, the same capture/parse/comparison may be implemented there, provided the self-tests pass. Do **not** claim either implementation works until its self-tests have been reviewed or executed safely.
* **Limitation:** Git stores paths as bytes; this parser decodes them as **strict UTF-8** (invalid sequences are a hard error — see §4.5). A repo path containing non-UTF-8 bytes would therefore fail closed rather than be silently mangled. This is intentional.

### 4.5 `[V2.2 CHANGE]` Structured parser for porcelain v1 `-z` (rename/copy aware)

**Record model (documented):**
* Normal entry: `XY<SP>PATH<NULL>` → record `{ X, Y, Path }`.
* Rename/copy (`X` in `R`/`C`): `XY<SP>NEWPATH<NULL>ORIGPATH<NULL>` → record `{ X, Y, Path, Orig }`. The **second NUL-terminated token is consumed as the original path**, not treated as an independent status line.
* With `-z`, paths are **not** quoted and **not** C-escaped — they are literal bytes. Line- and whitespace-based parsing is forbidden.
* `--porcelain=v1` `XY` uses `.` for "unchanged" in each column.

**Specification (proposed):**
```powershell
function Parse-GitStatusZ {
  param([Parameter(Mandatory)][string]$Path)
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $tokens = New-Object System.Collections.Generic.List[byte[]]
  $start = 0
  for ($i = 0; $i -lt $bytes.Length; $i++) {
    if ($bytes[$i] -eq 0) {
      $len = $i - $start
      $t = New-Object byte[] $len
      [Array]::Copy($bytes, $start, $t, 0, $len)
      $tokens.Add($t); $start = $i + 1
    }
  }
  if ($start -lt $bytes.Length) { throw 'MALFORMED: trailing bytes without NUL terminator' }
  # strict UTF-8: throws on invalid sequences (fail closed)
  $enc = New-Object System.Text.UTF8Encoding($false, $true)

  $recs = New-Object System.Collections.Generic.List[object]
  $i = 0
  while ($i -lt $tokens.Count) {
    $tk = $tokens[$i]
    if ($tk.Length -lt 4) { throw "MALFORMED record (len $($tk.Length)) at token $i" }
    if ($tk[2] -ne 0x20)  { throw "MALFORMED record (missing SP) at token $i" }
    $xy  = $enc.GetString($tk, 0, 2)
    $pth = $enc.GetString($tk, 3, $tk.Length - 3)
    if ($pth.Length -eq 0) { throw "MALFORMED empty path at token $i" }
    $X = $xy.Substring(0,1); $Y = $xy.Substring(1,1)

    if ($X -eq 'R' -or $X -eq 'C') {
      if ($i + 1 -ge $tokens.Count) { throw "MALFORMED rename/copy: missing original path token" }
      $orig = $enc.GetString($tokens[$i+1])
      if ($orig.Length -eq 0) { throw "MALFORMED rename/copy: empty original path" }
      $recs.Add([pscustomobject]@{ X=$X; Y=$Y; Path=$pth; Orig=$orig; Key="$xy|$pth|$orig" })
      $i += 2
    } else {
      $recs.Add([pscustomobject]@{ X=$X; Y=$Y; Path=$pth; Orig=$null; Key="$xy|$pth" })
      $i += 1
    }
  }
  return ,$recs
}
```
Fail-closed conditions (each throws → checkpoint STOP): trailing bytes without NUL · token shorter than 4 bytes · missing space separator · empty path · missing rename/copy original-path token · empty original path · any invalid UTF-8 sequence (via the strict encoder).

### 4.6 `[V2.2 CHANGE]` Structured comparison specification

**Inputs:** baseline records `B` (CP-0), current records `N`, `$AllowPaths` (exact repository-relative paths — §9.5).
**Outputs:** a list of violations (empty = pass). Any violation → **STOP**.

```powershell
function Compare-GitStatusRecords {
  param($Baseline, $Current, [string[]]$AllowPaths)
  $fail = New-Object System.Collections.Generic.List[string]
  $b = @{}; foreach ($r in $Baseline) { $b[$r.Path] = $r }
  $n = @{}; foreach ($r in $Current)  { $n[$r.Path] = $r }

  # (a) every baseline entry must still exist with the SAME key (status + paths)
  foreach ($r in $Baseline) {
    if (-not $n.ContainsKey($r.Path)) { $fail.Add("MISSING baseline entry: $($r.Path)") }
    elseif ($n[$r.Path].Key -ne $r.Key) {
      $fail.Add("STATUS TRANSITION: $($r.Path) ($($r.Key) -> $($n[$r.Path].Key))")
    }
  }
  # (b) every new entry must be exactly allowlisted and untracked-only
  foreach ($r in $Current) {
    if ($b.ContainsKey($r.Path)) { continue }
    $allowed = $false
    foreach ($a in $AllowPaths) { if ($r.Path -ceq $a) { $allowed = $true; break } }
    if (-not $allowed) { $fail.Add("ILLEGAL NEW PATH: $($r.Key)") }
    elseif ($r.X -ne '?') { $fail.Add("NON-UNTRACKED ADDITION (staging not permitted): $($r.Key)") }
  }
  return ,$fail
}
```
The comparator is **path-keyed and case-sensitive** (`-ceq`) to avoid conflating distinct paths on case-sensitive bases.

**In addition to the record comparison**, Gate B must run two independent checks:
* **(b1) Content hashes:** re-hash every pre-existing `M`/`??` entry from CP-0 and require exact equality with the CP-0 hash. (Catches an already-`M` file whose content changed again.)
* **(b2) Deletion persistence:** for each of the 12 pre-existing deleted paths, require the path to be **absent** on disk. (Catches an accidental restore.)

### 4.7 `[V2.2 CHANGE]` Mandatory self-tests (positive and negative)

The parser and comparator must pass these self-tests **in the environment used at CP-0**, against synthetic byte fixtures where a real repo state cannot be produced without staging. Results must be recorded; **do not invent outcomes**.

| # | Case | Fixture | Expected |
|---|---|---|---|
| T1 | Clean status | empty byte stream | 0 records; comparator(clean,clean,[]) = pass |
| T2 | Modified + deleted | ` M a.txt\0 D b.txt\0` | 2 records; identical baseline/current = pass |
| T3 | Untracked file + untracked dir file | `?? n.txt\0?? d/f.txt\0` | 2 records (with `-uall`, dir files listed individually) |
| T4 | Path with spaces | ` M "dir with space/f.txt"\0` (literal bytes) | path reproduced exactly, no truncation |
| T5 | Path with Unicode | `?? "café/π.txt"\0` (UTF-8 bytes) | path reproduced exactly |
| T6 | Rename record (both paths) | `R  new.txt\0old.txt\0` | **1** record with `Path=new.txt`, `Orig=old.txt` |
| T7 | Copy record (both paths) | `C  new.txt\0old.txt\0` | 1 record with `Orig=old.txt` |
| T8 | Unexpected new path | baseline empty; current `?? x.txt\0`; AllowPaths=[] | **ILLEGAL NEW PATH → fail** |
| T9 | Pre-existing change misclassified as implementation-owned | baseline ` M a.txt\0`; current ` M a.txt\0` with changed content hash | **(b1) hash mismatch → fail** |
| T10 | Malformed/incomplete record | `R  new.txt\0` (missing original path token) | **throw → fail closed** |
| T11 | Missing space separator | `M a.txt\0` | **throw → fail closed** |
| T12 | Invalid UTF-8 path bytes | `?? 0xFF 0xFE\0` | **throw → fail closed** |

Negative controls (must fail): T8, T9, T10, T11, T12. Positive controls (must pass): T1, T2, T3, T6, T7. T4/T5 verify exactness.

### 4.8 `[V2.2 CHANGE]` Failure behavior and limitations
* Any throw in capture/parse, any non-empty violation list, any hash mismatch, any deletion that reappeared, or any self-test failure → **STOP the checkpoint and report**.
* Never resolve a failed check by staging, restoring, deleting, cleaning, or otherwise manipulating a file.
* Documented limitations: strict-UTF-8 decoding (non-UTF-8 paths fail closed); compares path+status+content only, not metadata (see §3.4 guarantee scope); rename/copy self-tests use synthetic fixtures because producing real renames requires staging, which is forbidden.

---

## 5. Secrets and Local Configuration `[CARRY]`

* Source `android/local.properties` contains `MAPS_API_KEY`, `sdk.dir`, `flutter.sdk`. **Never copy. Never print. Never embed in this plan, logs, manifests, reports, screenshots.**
* Hash for integrity only (`Get-FileHash`).
* Target must be checked for the **absence** of a copied source `local.properties`.
* Target-local config is generated only during implementation, as authorized: the developer's own SDK paths plus the existing mechanism — **HYPOTHESIS** `local.properties → environment variable → "" fallback` (`android/app/build.gradle.kts:37-40`); **CP-0 must verify**.
* No secret value may appear in any manifest diff output.

---

## 6. Outdoor/Indoor Classification, Strict MVVM, Indoor Absence `[CARRY]`

Classification is by **method + call site + dependency**, never by file or directory name. A file may appear in more than one row.

### 6.1 Routing classification (F1, F2, F3, F5)

| Item | Refs | Class | Required action |
|---|---|---|---|
| `NavigationRepository.getRouteFromCoordinates` | `navigation_repository.dart:21` (decl), `:62` (impl) | **SHARED** | **Preserve.** Outdoor reroute passes `floorNumber: null` (`navigation_deviation_handler.dart:259-275`) and adopts raw geometry at `:297-298`. Trim Indoor call sites only. |
| `NavigationRepository.getRouteBetweenPois` | `:16` (decl), `:54` (impl) | **INDOOR** (provisional, HYPOTHESIS) | Inspect all callers before removal. Reported callers: `cross_building_router.dart:990,1210`; `routing_service.dart:125`; `campus_route_coordinator.dart:398,513,745,1011,1046`; `space_view_model.dart:722` (doc ref). |
| `NavigationRepository.getOutdoorWalkingRouteWithMetadata` | used `cross_building_router.dart:450,467,626,797` | **OUTDOOR** | Preserve. |
| `routing_service.dart` connector builder | `:80-169`, call `:125` | **INDOOR** (HYPOTHESIS) | Preserve independent Outdoor cascade; inspect callers before removal. |
| `cross_building_router._generateOutdoorSegment` | `:450,467,626,797` | **OUTDOOR** | Preserve. |
| `cross_building_router._generateExitSegment` | `:343`; indoor call `:366`; fallback `:355,359,393` | **MIXED** | See 6.2. |
| `cross_building_router._generateEntranceSegment` | `:964`; indoor `:990,1015`; connectors `:1044`; fallbacks `:977,981,1072` | **MIXED** | See 6.2. |
| `cross_building_router._routeViaConnectors` | `:1134`; indoor `:1210`; caller `:1044`; test hook `:1260` | **INDOOR** (HYPOTHESIS) | Removal breaks `remediation_crossbuilding_test` NAV-003 (§7). |
| `cross_building_router.composeRoute` | decl `:71`; callers `campus_route_coordinator.dart:259,604` | **MIXED / LIVE** | **Not dead code** (F2). |
| `_detectBuildingFromPolygon` / `detectUserBuilding` | `cross_building_router.dart:273`; coordinator `:246` | **OUTDOOR (geometry)** | Floor-bounds containment; no Wi-Fi required. Preserve. |
| `navigation_deviation_handler` Step-2 reroute | `:256-310` | **MIXED** | Outdoor branch `:259-261`,`:297-298`; indoor branch `:299-302` (`toSegmentedIndoor`). Trim Indoor branch only. |
| `NavigationState.{enteringBuilding,activeIndoor,exitingBuilding}` | `navigation_state.dart` | **UNRESOLVED (U2)** | Enumerate all states/transitions/handlers/consumers/tests first. |

`[CARRY]` All line references above are **HYPOTHESIS** until CP-0 body-read confirms them.

### 6.2 `[CARRY]` F2 — `composeRoute` behavior must be reviewed, not assumed
`composeRoute` is reached whenever the user is outside the destination building (`campus_route_coordinator.dart:246-276`), via polygon geometry. Its Indoor exit/entrance legs are reachable on ordinary cross-building routes while the user stands inside any building polygon. Removing them yields straight-line `exitTransition`/`entranceTransition` with `isIncomplete: true` → `hasIncomplete` (`cross_building_router.dart:202`) → `partialRouteWarning` (`:223`) → UI (`campus_route_coordinator.dart:268`, `navigation_status_bar.dart:90`).

Obligations: not dead code · straight-line/incomplete/`partialRouteWarning` **not** pre-accepted · body-level review of `:71-342`, `:343-449`, `:964-1133` before decisions · determine whether Outdoor behavior is preservable without Indoor runtime deps · **CP-7B approval gate** for any necessary behavior change · no silent redesign.

### 6.3 `[CARRY]` Strict MVVM — responsibility-based acceptance

| Layer | Must hold | Assertion (≥1 per moved responsibility) |
|---|---|---|
| View | Renders state; forwards intent; **no multi-step orchestration**; **no business-provider writes** | `_startDirectionsForPoi`-equivalent contains no sequential VM command chain and no `ref.read(...notifier).state =` for business workflows |
| ViewModel | No Flutter widgets, no `GoogleMapController`, no camera/rendering calls | static scan of `lib/viewmodels/` for `Widget|GoogleMapController|animateCamera|moveCamera` |
| Service/use case | Owns data access + platform integration | unit tests run without a widget tree |
| Repository | Method-level Indoor/Outdoor/shared separation | §6.4 dependency map |
| Model/domain/shared state | No presentation-widget dependency | no `import 'package:flutter/material.dart'` in `lib/models/`, nav services |
| Navigation transitions / routing decisions | Testable without Flutter UI | state-machine + router tests pass headlessly |
| UI callbacks / controller ops | Explicit boundary | callback-interface test |
| Runtime graph | No Indoor positioning/radiomap dependency | §6.4 zero-reachable-hit proof |

Compilation is **not** evidence of MVVM compliance.

### 6.4 `[CARRY]` Indoor-absence proof — text search is insufficient

Required combination (all at CP-3 / CP-5 / CP-10):
1. **Dependency map** from Outdoor runtime entry points (`main.dart` → provider tree → views → viewmodels → services/repositories → platform channels → native → assets) down to each Indoor candidate.
2. **Registration/call-site inspection:** imports, constructor/`Provider`/Riverpod registrations, DI wiring, direct call sites, `MethodChannel`/`EventChannel` registrations, plugin/permission requirements.
3. **Hit classification:** classify every search result as production dependency / test / dead code / comment / harmless reference.
4. **Reachability proof:** no reachable Outdoor runtime path depends on Indoor positioning, radiomap, floorplan rendering, or Indoor POI routing.
5. **Regression confirmation:** retained Outdoor features still work.

**Removal-safety verifier (proposed, read-only):**
```powershell
rg -n "getRouteBetweenPois|_routeViaConnectors|NativePositioningService|latestIndoorEstimate|isIndoorWifiActive|loadRadioMap|resetAllRadiomaps" lib test android
```
Every hit must be classified per item 3 before any deletion. Any unclassified production hit → **STOP**.

Do not delete shared files or native components until consumers are traced. Preserve heading, required location capabilities, and Outdoor floor-selection behavior where the design requires them.

### 6.5 `[CARRY]` Location / native / assets (REPORTED/HYPOTHESIS — CP-0 verifies)

| Item | Refs | Class | Action |
|---|---|---|---|
| `MethodChannelNativePositioningService()` | `main.dart:21-24` | INDOOR | remove after dependency map |
| `positionStream` subscription | `location_view_model.dart:227` | MIXED | split GPS vs Wi-Fi |
| Radiomap fallback → `CampusAssetLoader` | `space_view_model.dart:92-100` | INDOOR | verify callers |
| Radiomap load/reset | `campus_asset_loader.dart:285-389`, `:602` | INDOOR | |
| Indoor exposure to pilot | `navigation_view_model.dart:82-89` | INDOOR | consumers: `NavigationPilot` |
| Floors + POIs | `poisForBuildingFloor`, `floorNumbersForBuilding`, `BuildingContainment` | **SHARED** | **Keep** |
| `orientation/DeviceHeadingBridge.kt` | channel `…/heading_stream:44` | OUTDOOR | **Keep** |
| `positioning/{PositioningBridge,KnnLocalizer,PositioningEngine,RadioMap,WifiScanner}.kt` | — | INDOOR | remove only after CP-3 dependency map |
| `MainActivity.kt` constructs both | `:10,17,19-21,25-27` | MIXED | split |
| Permissions `ACCESS_WIFI_STATE`, `CHANGE_WIFI_STATE`, `NEARBY_WIFI_DEVICES` | manifest | INDOOR-candidate | remove only after inspecting all remaining plugin/native requirements |
| `INTERNET`, `ACCESS_FINE/COARSE/BACKGROUND_LOCATION`, `FOREGROUND_SERVICE(+_LOCATION)` | manifest | OUTDOOR | keep |
| `assets/config/gate_policy.json`, `assets/config/university gates.kmz`, `assets/navigation/university roads.kmz` | 3 files | **OUTDOOR** | preserve (gate policy `G2` preferred; `G1`,`G3`,`G4` disabled — verify at CP-0) |
| `network_security_config.xml:11` empty `<domain>` | — | observation | log only; do not "fix" |

### 6.6 `[CARRY]` MapScreen / CampusContentPanel responsibilities (REPORTED/HYPOTHESIS — CP-0 verifies)

* `map_screen.dart`: heading service construction `:98-99`; heading subscription `:148`; bitmap synthesis `:184-419`; camera math `:607-992`; floorplan overlay cache/async prepare/`setState` `:1298-1370`; marker/route projection `:1057-1289`. Extracted: `computeRouteCamera` `:1538-1572` (**contract must be preserved or an approved test/API migration documented**), `routePolylineSpecs`, `showCampusRoutes`, `BuildingContainment`.
* `campus_content_panel.dart` (F6): `_startDirectionsForPoi` `:1329-1360` (View-owned ~6-step orchestration incl. provider write `:1359`); `_fitRouteBoundsIfAvailable` `:1314-1317` (View→Map camera callback); `_buildBuildingRouteActions` `:1077-1133` (action state derived from 3 ViewModels); Indoor copy `:974`; floor chips `:984-992` (**keep** — floor-bounds containment + floor-scoped POI selection).

MVVM actions: move orchestration to a ViewModel/use-case; keep camera behind an explicit UI callback (**do not** move camera into a ViewModel); relocate derived action state; rewrite Indoor copy only; keep floor chips.

---

## 7. Test Inventory and Regression Matrix `[CARRY]`

### 7.1 46-vs-47 discrepancy — RESOLVED (V2.1 planning pass, read-only)
**CONFIRMED (V2.1 planning pass):**
```
test/*_test.dart (recursive, runnable)      = 46
test/*.dart.disabled (recursive)            = 4
test/*.dart (recursive, all)                = 47
test/helpers/fake_google_maps_platform.dart = 1  (the 47th .dart, not runnable)
```
Interpretation: both prior counts were partially right — 46 runnable tests and 47 total `.dart` files (the helper is the extra). No file was renamed. CP-0 must re-run this inventory and record the exact file list; all later counts compare to that baseline. **No final counts are invented.**

### 7.2 Per-test / per-assertion classification
Classes: **Preserve** · **Adapt** · **Exclude** (written justification) · **Add**.

`test/remediation_crossbuilding_test.dart` (mixed — split per test):

| Case | Refs | Hook | Class | Reason |
|---|---|---|---|---|
| NAV-002 nearest ground entrance | `:127-142` | `selectExitPoiForTest` | **Preserve** | Outdoor entrance selection |
| NAV-003 connector chain returns null | `:144-164` | `routeViaConnectorsForTest` | **Adapt or Exclude — CP-0 decision** | Depends on `_routeViaConnectors` (Indoor) |
| B7 outside-bounds | `:166-184` | `detectUserBuilding` | **Preserve** | building containment |
| B7 inside-bounds | `:186+` | `detectUserBuilding` | **Preserve** | building containment |
| Remaining cases | not yet read | — | **UNRESOLVED — CP-0** | |

Indoor-leaning candidates (per-case classification, **not** permission to delete whole files): `location_provider_arbitration_test`, `radiomap_lifecycle_test`, `floor_transition_test`, `handoff_guidance_test`, `position_estimate_boundary_test`; Indoor cases inside `navigation_ui_test`, `navigation_state_machine_test`.

Must preserve: `custom_routes_test`, `custom_route_connectivity_test`, Outdoor cases in `remediation_crossbuilding_test`, outdoor reroute + null-floor behavior (F1), B7 detection, NAV-002, graph-connectivity + gate-policy assertions, `camera_math_test`.

### 7.3 Environment facts (REPORTED — verify)
* `custom_route_connectivity_test.dart` reads `assets/navigation/university roads.kmz` by relative path → run tests **from the target app directory**; verify path assumptions.
* Widget tests require `test/helpers/fake_google_maps_platform.dart` / `installFakeGoogleMapsPlatform()` → verify and preserve.
* `test/live_integration_smoke_test.dart` opt-in via `--dart-define=LIVE_SMOKE=true` → keep separate; never assume external services.
* 4 `*.dart.disabled` files are excluded by the Dart runner — **do not rename to restore coverage**.

### 7.4 New tests required
Outdoor reroute with `floorNumber: null`; Indoor runtime-absence (§6.4); each §6.3 responsibility boundary; target identity + heading-channel; Gate A / A′ / A″ / B proofs.

---

## 8. `[V2.2 CHANGE]` Authorization, Sequencing, and Checkpoints

### 8.0 Authorization and checkpoint sequencing (Correction B)

**Three distinct concepts that never imply one another:**
* **Technical verification** — running scripts/tests and recording evidence. Proves only what was measured.
* **Plan acceptance** — the user accepting a plan revision as the reference. Grants no code changes.
* **Implementation authorization** — the user's separate, explicit message authorizing a specific checkpoint. Required before any application file is created/modified/deleted.

**Explicit sequence:**
1. **Current authorization (this task):** create and verify `docs/PHASE_1_PLAN_V2.2_REVIEW.md` only. Nothing else. No application work.
2. **CP-0** is read-only preflight and evidence collection. No application implementation.
3. **After CP-0:** STOP. Present findings, resolved/unresolved questions, risks, the **exact proposed file allowlists**, and any required decisions to the user.
4. **Do not begin CP-1 or any later checkpoint** until the user gives **separate, explicit** authorization after reviewing the CP-0 findings.
5. **CP-7A remains read-only** routing analysis. It must not silently transition into CP-7B.
6. **CP-7B requires a separate explicit authorization** after CP-7A findings have been presented and reviewed.
7. If removing Indoor functionality would alter **observable Outdoor behavior**, STOP the affected work and explain the specific behavior, evidence, impact, and alternatives. Obtain explicit user approval **before** making that behavior change.
8. **An approval for one checkpoint or behavior change does not authorize any other** checkpoint or behavior change.
9. **No automatic continuation** from a completed checkpoint into the next.

Per checkpoint: **Preconditions · Actions · Evidence · Pass · Fail · Must remain unchanged · Next allowed · Exact-path allowlist to be approved.** No claim of success without recorded evidence; no invented outputs.

### CP-0 — Read-only preflight and baseline
* **Preconditions:** none. **No copy or edit until CP-0 is complete, presented, and separately approved.**
* **Actions:** capture baseline (git branch/HEAD/**byte-exact** `-z` capture per §4.4-4.5, pre-existing hashes, deleted-path list) · run Gate B parser self-tests (§4.7) · full-source manifest (M1) · record target/source dir state · verify Android/Kotlin/Gradle/Java/Flutter/Dart config + `.metadata` revision + manifest + gradle + settings + channels · inventory `lib/`, `test/` (re-run §7.1), `assets/` (expect 3) · **body-level read of every unresolved item (register P1–P8)** · complete per-test classification · review route composition and incomplete-transition behavior · review `map_screen.dart`, `campus_content_panel.dart`, location/nav/repository/native bodies · resolve U2–U10; recover A1–A7 · validate copy method via `/L` dry run · verify the byte-safe runtime (PowerShell version, or Python) is available.
* **Evidence:** `$audit` files (raw status bytes + parsed records + hashes), M1 manifest, `cp0_inventory.txt`, `cp0_unresolved_register.txt`, dry-run listing, self-test results.
* **Pass:** every register row has a recorded finding; no contradiction open; parser self-tests pass.
* **Fail:** any required path unresolved/truncated/assumption-based; key assumption contradicted; route-behavior impact not understood; counts unreconciled; self-tests fail.
* **Unchanged:** entire repository (read-only).
* **Next:** **STOP and present findings for the user's review.** Proceed only after a **separate explicit authorization.** If Outdoor behavior cannot be preserved without user-visible regression → return findings, ask for decision, **STOP**.

**Preflight register (each: what to read / how recorded / decision gated / stop trigger)**

| # | Read/verify | Record as | Gates decision | Stop trigger |
|---|---|---|---|---|
| P1 | full `cross_building_router.dart` bodies (composition, exit/entrance transitions, incomplete handling, outdoor generation) | finding note + refs | F2; CP-7A | truncated read, or outcome contradicts an assumption → **stop & report** |
| P2 | full `campus_content_panel.dart` bodies | finding note + refs | CP-8 | same |
| P3 | U2–U10 status | per-item | §6 boundaries | unresolved at end of CP-0 |
| P4 | all call sites for each proposed Indoor removal | dependency map | CP-3/CP-5/CP-7B | any Outdoor consumer |
| P5 | every test/assertion affected by API/behavior change | classification table | CP-9 | an assertion would be weakened |
| P6 | exact test/file inventory; re-resolve 46 vs 47 | `cp0_inventory.txt` | D9; CP-9 | counts irreconcilable |
| P7 | Android identity, Flutter import structure, build config, assets, native channels | config record | §3.3; CP-2 | undocumented deviation |
| P8 | recover A1–A7 verbatim from prior plan | assumption log | §11.2 | not recoverable → mark unverified |

### CP-1 — Initial sibling copy
* **Preconditions:** CP-0 complete; user separately authorized CP-1; dry-run validated; **exact-path allowlist for all target files approved** (§9.4).
* **Actions:** create target; run §3.1 copy; preserve required untracked wrappers; exclude source `local.properties` + §3.2 items; do not alter source; verify required-file presence + Gate A.
* **Evidence:** copy exit code (`$rc` captured immediately), presence list, M2 diff.
* **Pass:** `$rc < 8`; zero unexplained differences.
* **Fail:** any copy error, unexpected diff, missing required file, source change, or any diff outside the approved allowlist.
* **Unchanged:** source; pre-existing entries.
* **Next:** only on pass **and** user authorization for CP-2.

### CP-2 — Target-local config and build identity
* **Preconditions:** CP-1 passed; user separately authorized CP-2; **AL-2 exact-path list instantiated and approved**.
* **Actions:** confirm target has no copied source `local.properties`; create target-local config only as authorized; apply §3.3 identity edits; keep toolchain versions; run Gate A′ against the approved **AL-2**.
* **AL-2 (template — must be instantiated with exact paths before CP-2):** the Android build file(s) holding `namespace`/`applicationId` · the Kotlin source files whose package declaration and channel string change · the app-label resource file · the Dart heading-channel constant file. Only identity/label/channel/config paths; **no Indoor-removal, MVVM, routing, or test paths.**
* **Evidence:** absence check, identity grep, Gate A′ diff (each diff = exactly one approved path).
* **Pass:** no secret present/exposed; identity consistent; every diff matches one approved AL-2 path.
* **Fail:** secret exposure, identity inconsistency, any diff outside AL-2.
* **Next:** only on pass **and** user authorization for CP-3.

### CP-3 — Native Indoor runtime removal
* **Preconditions:** CP-2 passed; user separately authorized CP-3; P4 native dependency map complete; **AL-3 exact-path list approved**.
* **Actions:** keep `DeviceHeadingBridge.kt`; remove positioning bridge wiring + verified Indoor native files; revise `MainActivity.kt`; review permissions against actual remaining plugin/native requirements; confirm atomic channel rename; run §6.4 verifier; Gate A′ against **AL-3**.
* **AL-3:** the exact removed native file paths · `MainActivity.kt` · the exact manifest path.
* **Pass:** heading intact and renamed atomically; §6.4 reachability proof shows zero Indoor runtime dependency.
* **Fail:** any required Outdoor capability depends on a proposed removal; any unclassified hit.
* **Next:** only on pass **and** user authorization for CP-4.

### CP-4 — MapScreen MVVM boundaries *(before CP-6 overlay removal)*
* **Preconditions:** CP-3 passed; user separately authorized CP-4; full `map_screen.dart` body read; **AL-4 exact-path list approved**.
* **Actions:** body inspection; responsibility inventory; extract pure logic to testable helpers; keep controller/rendering UI-side; preserve `computeRouteCamera` contract or document approved migration; add responsibility tests; Gate A′ against **AL-4**.
* **AL-4:** the exact `map_screen.dart` path · each exact new/changed helper/service file path · each exact corresponding test file path.
* **Pass:** responsibility tests pass; no controller/rendering in ViewModels; Outdoor rendering/routing unchanged.
* **Fail:** behavior change or boundary violation.
* **Next:** only on pass **and** user authorization for CP-5.

### CP-5 — Location and positioning split
* **Preconditions:** CP-4 passed; user separately authorized CP-5; location dependency map complete; **AL-5 exact-path list approved**.
* **Actions:** split Outdoor GPS from Indoor Wi-Fi/radiomap lifecycle; remove Indoor service deps from Outdoor runtime graph; preserve GPS streams/fallback/rerouting; verify all consumers; add lifecycle + outdoor-routing-integration tests; Gate A′ against **AL-5**.
* **AL-5:** each exact location/positioning viewmodel, service, and repository path changed · each exact corresponding test path.
* **Pass:** Outdoor location + rerouting semantics unchanged; §6.4 proof.
* **Fail:** split breaks Outdoor location or rerouting.
* **Next:** only on pass **and** user authorization for CP-6.

### CP-6 — Indoor map/floorplan/radiomap removal *(after CP-4)*
* **Preconditions:** CP-5 passed; user separately authorized CP-6; overlay/cache seam read; **AL-6 exact-path list approved**.
* **Actions:** remove verified Indoor-only pipeline; preserve hybrid basemap, markers, road/gate overlays, Outdoor route display; preserve floor selection for containment/POI selection; rewrite Indoor copy; Gate A′ against **AL-6**.
* **AL-6:** each exact Indoor overlay/floorplan/radiomap file path · the exact panel-copy file path · each exact corresponding test path.
* **Pass:** no residual Indoor runtime dependency; building/POI/routing intact.
* **Fail:** loss of required Outdoor building/POI/routing functionality.
* **Next:** only on pass **and** user authorization for CP-7A.

### CP-7A — Read-only routing impact analysis *(no implementation)*
* **Preconditions:** CP-6 passed; user separately authorized CP-7A; P1/P3/P4 complete.
* **Actions (read-only):**
  1. Inspect complete implementations + call sites of `composeRoute`, `_generateExitSegment`, `_generateEntranceSegment`, and all related transitions.
  2. Trace the **normal outdoor cross-building route** and the **outdoor rerouting** flows end-to-end.
  3. Establish how Indoor-related legs affect current Outdoor behavior.
  4. Identify potential incomplete routes, straight-line transitions, missing entrance/exit legs, and `partialRouteWarning` changes.
  5. Record concrete test cases + expected behavior for each identified scenario.
* **Evidence:** routing-impact analysis (call graphs, scenario table, before/after route-shape expectations).
* **Pass:** every route scenario has a documented current behavior and a documented expected post-change behavior, each with a test.
* **Fail:** any scenario unresolved; any read truncated.
* **Unchanged:** all code (read-only).
* **Next:** **present CP-7A findings for the user's review. Do NOT proceed into CP-7B.** CP-7A must not silently become CP-7B.

### CP-7B — Routing implementation after explicit authorization
* **Preconditions:** CP-7A findings **reviewed by the user** and a **separate, explicit authorization** granted for CP-7B (and, if applicable, for any required observable Outdoor behavior change); **AL-7 exact-path list approved**.
* **Actions:**
  * If existing Outdoor behavior is preservable → document how, and prove it with regression tests.
  * If safe Indoor removal necessarily changes Outdoor behavior → **STOP.** Present the exact proposed behavior change, evidence, and alternatives. **Do not choose an alternative or implement it without explicit approval.**
  * Preserve shared coordinate routing + `getRouteFromCoordinates`; preserve Outdoor rerouting, graph routing, entrance selection, route metadata; verify method-level `NavigationRepository` separation; Gate A′ against **AL-7**.
* **AL-7:** each exact routing/repository file path changed · each exact corresponding test path.
* **Evidence:** scenario results vs CP-7A expectations; regression tests; approval record.
* **Pass:** behavior matches CP-7A-approved expectations, **or** an approved behavior change is implemented exactly as approved.
* **Fail:** any unapproved observable change; compilation/tests alone are **not** proof of behavior preservation.
* **Next:** only on pass **and** user authorization for CP-8.

### CP-8 — CampusContentPanel MVVM refactor
* **Preconditions:** CP-7B passed/approved; user separately authorized CP-8; P2 complete; **AL-8 exact-path list approved**.
* **Actions:** move orchestration to ViewModel/use-case; keep camera behind explicit UI callback; relocate derived action state; preserve floor chips; rewrite Indoor copy; add §6.3 tests; Gate A′ against **AL-8**.
* **AL-8:** the exact `campus_content_panel.dart` path · each exact new/changed ViewModel/use-case file path · each exact corresponding test path.
* **Pass:** View has no business orchestration/business-provider writes; ViewModel has no widget/controller ops.
* **Fail:** either condition true.
* **Next:** only on pass **and** user authorization for CP-9.

### CP-9 — Test migration and verification
* **Preconditions:** CP-8 passed; user separately authorized CP-9; §7 classification approved; **AL-9 exact-path list approved**.
* **Actions:** apply per-test classification; preserve Outdoor assertions; adapt only changed contracts; exclude only proven Indoor-only tests with written per-case justification; add §7.4 tests; run offline tests **from the target dir**; keep live tests opt-in; record commands + exit codes + counts; Gate A′ against **AL-9**.
* **AL-9:** each exact test file path created/modified/deleted, with its classification.
* **Pass:** no weakened assertions; Outdoor assertions green; results explainable vs CP-0 baseline.
* **Fail:** tests weakened; Outdoor assertion fails; unexplained delta.
* **Next:** only on pass **and** user authorization for CP-10.

### CP-10 — Final acceptance and integrity
* **Preconditions:** CP-9 passed; user separately authorized CP-10.
* **Actions:** Gate A″ (M1) · Gate B (§4) · Gate A′ re-run · Outdoor routing/rerouting regressions · gate policy + graph topology · §6.4 Indoor-absence proof · §6.3 MVVM checks · identity/channel consistency · API-key confidentiality · final inventory + exact test results.
* **Pass:** every mandatory gate verified with evidence. **Do not claim success if any gate is unverified.**

---

## 9. Integrity Gates

All commands are **proposed, not executed**. Common rules: `Get-ChildItem -Force` (hidden files) · relative normalized paths · sorted entries · SHA-256 · identical exclusions on both sides of every excluded comparison · **never print file contents** · output to `$env:TEMP\campusfind_v2_2_audit` (outside the repo).

### 9.1 Core helpers (root-safe, hidden-inclusive)
```powershell
function Get-TreeManifest {
  param([string]$Root,
        [string[]]$ExclDirs  = @('.dart_tool','build','.gradle','.kotlin','.idea','.vscode'),
        [string[]]$ExclFiles = @('local.properties','.flutter-plugins-dependencies','GeneratedPluginRegistrant.java'),
        [string[]]$ExclPaths = @())
  $rf = (Resolve-Path -LiteralPath $Root).Path
  Get-ChildItem -LiteralPath $rf -Recurse -Force -File | ForEach-Object {
    $rel = $_.FullName.Substring($rf.Length).TrimStart('\','/').Replace('\','/')
    $parts = $rel -split '/'
    $name  = $parts[-1]                                  # root-safe (no invalid slicing)
    $dirs  = if ($parts.Count -gt 1) { $parts[0..($parts.Count-2)] } else { @() }
    $okDir  = -not ($dirs  | Where-Object { $ExclDirs  -contains $_ })
    $okFile = -not ($ExclFiles -contains $name)
    $okPath = -not ($ExclPaths -contains $rel)
    if ($okDir -and $okFile -and $okPath) {
      [pscustomobject]@{ Path = $rel
                         Hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    }
  } | Sort-Object Path
}
function Compare-TreeManifest {
  param($A, $B)
  $ha = @{}; $A | ForEach-Object { $ha[$_.Path] = $_.Hash }
  $hb = @{}; $B | ForEach-Object { $hb[$_.Path] = $_.Hash }
  foreach ($p in (@($ha.Keys + $hb.Keys) | Sort-Object -Unique)) {
    if ($ha[$p] -ne $hb[$p]) {
      [pscustomobject]@{ Path = $p
        SourceHash = $(if ($null -eq $ha[$p]) { '<MISSING>' } else { $ha[$p] })
        TargetHash = $(if ($null -eq $hb[$p]) { '<MISSING>' } else { $hb[$p] }) }
    }
  }
}
```
Guarantee scope: path + content only (see §3.4). Hashes only — secrets can appear solely as hashes.

### 9.2 Gate A — Initial copy equivalence (CP-1)
Identical §3.2 exclusions on both sides: source vs target via `Get-TreeManifest` + `Compare-TreeManifest`. **Pass:** empty diff. **Fail:** any diff → **STOP; never normalize silently.** This proves only that *included* files match.

### 9.3 Gate A″ — Original source integrity (CP-10)
No exclusions at all (hidden + local config + generated + untracked), compared against M1. **Pass:** exact equality. **Fail:** any difference → **STOP immediately; do not auto-repair.** Secrets only as hashes.

### 9.4 `[V2.2 CHANGE]` Gate A′ — per-checkpoint **exact-path** allowlists (Correction C)

Rules:
1. Before each implementation checkpoint, **inspect the actual repository** and prepare an explicit list of **every** file the checkpoint is permitted to create, modify, or delete.
2. Use **exact repository-relative paths**. A broad directory, wildcard, glob, or category (e.g. "new tests") is **not** authorization.
3. If the complete file list cannot be established before the checkpoint, **STOP** and present the proposed list for user approval before editing.
4. **New files require exact-path authorization** the same as modifications and deletions.
5. A file is **not** automatically authorized merely because it is under `clients/flutter/campusfind_outdoor/`.
6. An unexpected changed path, an unplanned deletion, or an unapproved file creation → **STOP the checkpoint immediately**.
7. Compare actual changes against the approved exact-path allowlist **and** the preserved pre-existing baseline; do not confuse the two.
8. Never resolve a failed allowlist check by restoring, deleting, staging, or otherwise manipulating an unexpected file. **Stop and report.**
9. Keep the source application untouched, including pre-existing modifications/deletions.
10. Documentation exceptions are also **exact paths** and explicitly justified.

**Allowlist register (each must be instantiated with exact paths and approved before its checkpoint runs):**

| Allowlist | Checkpoint | Exact-path set (to be instantiated) |
|---|---|---|
| AL-2 | CP-2 | exact Android build file(s) for `namespace`/`applicationId` · exact Kotlin files (package + channel) · exact label resource · exact Dart channel-constant file |
| AL-3 | CP-3 | exact removed native files · exact `MainActivity.kt` · exact manifest |
| AL-4 | CP-4 | exact `map_screen.dart` · exact new helper/service files · exact test files |
| AL-5 | CP-5 | exact location/positioning files · exact test files |
| AL-6 | CP-6 | exact Indoor overlay/floorplan/radiomap files · exact panel-copy file · exact test files |
| AL-7 | CP-7B | exact routing/repository files · exact test files |
| AL-8 | CP-8 | exact `campus_content_panel.dart` · exact new ViewModel/use-case files · exact test files |
| AL-9 | CP-9 | exact test files, each with its §7 classification |

Each allowlist entry states: **exact path · reason expected to change · authorizing checkpoint · behavior-vs-structure flag.**
**Pass:** every diff matches exactly one enumerated entry. **Fail:** any unmatched diff → **STOP.** Original-source integrity (§9.3) remains independent of copy equivalence (§9.2) and target-local changes (§9.4).

### 9.5 `[V2.2 CHANGE]` Gate B — baseline-aware worktree preservation (byte-safe)

See §4.3–§4.8. **Pass:** no missing baseline entry; no status transition on a pre-existing entry; no pre-existing content-hash change; all 12 deletions still absent; every new path is on the **exact** §9.5 allowlist. **Fail → STOP.** Never restore/clean/stage pre-existing work.

**Documentation and plan-artifact policy (exact paths):**

* The **only** permitted new non-target entries are the two immutable review artifacts, listed **exactly**:
  1. `docs/PHASE_1_PLAN_V2.1_REVIEW.md` (historical, immutable)
  2. `docs/PHASE_1_PLAN_V2.2_REVIEW.md` (this revision)
* **No filename-pattern authorization.** A future file merely matching `PHASE_1_PLAN_*.md` or similar is **not** permitted and must fail Gate B.
* **The implementation-authoritative plan is `docs/PHASE_1_PLAN_V2.2_REVIEW.md` only after the user explicitly approves it.** Before that approval, no plan file is authoritative.
* **Implementation must not modify either plan artifact.** They are read-only references. If either artifact's content hash changes during implementation, that is an unexpected change → **STOP**.
* Both artifacts are, in practice, pre-existing `??` entries in the implementation baseline (captured at CP-0), so Gate B preserves them by the ordinary pre-existing-entry rule.

Status equality is necessary but **not sufficient**; Gate A″ (§9.3) + recorded content hashes (§4.6b1) are the independent proof.

---

## 10. Risks R1–R12 (+R13)

Each: mitigation · verification evidence · STOP.

| ID | Risk | Mitigation | Evidence | STOP |
|---|---|---|---|---|
| R1 | Accidental source modification | source read-only throughout | Gate A″ | any source hash drift |
| R2 | API-key leakage | never copy/print `local.properties`; hash only; ban key in logs | absence check + secret scan | any key value outside source |
| R3 | Incorrect manifest exclusions | §3.2 table; identical both sides; separate full-source manifest | Gates A/A′/A″ | unexplained diff |
| R4 | Hidden/untracked build-critical files omitted | `-Force`; robocopy `/L`; wrapper checklist | presence list | required file missing |
| R5 | Broken Android package/channel identity | atomic identity edit set (§3.3) | identity grep + AL-2 entries | Dart/Kotlin channel mismatch |
| R6 | Residual Indoor runtime dependencies | §6.4 layered proof | dependency map | any reachable Indoor hit |
| R7 | Outdoor rerouting regression from deleting shared routing APIs | **F1: keep `getRouteFromCoordinates`**; null-floor reroute test | reroute test | reroute differs from baseline |
| R8 | Incomplete-route / `partialRouteWarning` regression | **F2 + CP-7A/7B gate** | route-shape comparison | unapproved behavior change |
| R9 | Loss of Outdoor function via over-removal of floor/POI data | floors+POIs SHARED; floor chips kept; per-call-site inspection | building/POI/routing regressions | any such test fails |
| R10 | MVVM refactor changes behavior or moves controller ops into VMs | §6.3 boundaries + tests | responsibility assertions | VM owns widgets/controller, or behavior changes |
| R11 | Test suite weakened by broad deletion/exclusion | per-test classification + written justification | disposition table | any assertion weakened |
| R12 | Destruction/restoration of pre-existing worktree changes | Gate B; never restore/stage/clean | Gate B output | missing/altered pre-existing entry |
| R13 | Approval-gate bypass (implementing a behavior/checkpoint change before written approval) | §8.0 sequencing + CP-7B preconditions + approval record | approval record | any change without an approval record |
| R14 `[V2.2 ADDITION]` | Gate B parser silently mis-parses (NUL loss, rename mishandling, encoding) | byte-safe capture + structured parser + §4.7 self-tests, fail-closed | self-test results recorded at CP-0 | any self-test fails; any malformed/ambiguous record |
| R15 `[V2.2 ADDITION]` | Allowlist too broad (directory/glob) hides an unexpected change | exact-path rule (§9.4) | per-checkpoint allowlist diff | any diff not matching exactly one exact path |

---

## 11. Uncertainties U1–U10 and Assumptions A1–A7 `[CARRY]`

### 11.1 U1–U10
Each unresolved item states: **what is unknown · files/refs needed · checkpoint to resolve · blocking condition.**

| ID | Unknown | Needed | Resolve at | Blocks |
|---|---|---|---|---|
| U1 | Full indoor-leg line ranges in `cross_building_router.dart` (`_generateExitSegment`, connector legs, `_selectExitPoi` scope) | complete body read | CP-0 (P1) | CP-7A |
| U2 | `RouteSegmentType.{indoorRouting,floorTransition}` consumers + `toSegmentedIndoor` | grep + reads | CP-0 (P3) | CP-7A/7B |
| U3 | `NavigationPilot` call sites into building-context/floor-transition handlers | reads | CP-0 (P3) | CP-5/CP-7B |
| U4 | `NavigationSessionManager` dwell/activity-restore bookkeeping | reads | CP-0 (P3) | CP-7B |
| U5 | `NavigationConfig` orphan constants | reads | CP-0 (P3) | CP-6 |
| U6 | `NavigationRouteScope.activeFloorplan` / `releaseIndoorContextForNavigation` / `selectFloorForNavigation` consumers | reads | CP-0 (P3) | CP-6/CP-7B |
| U7 | `campus_content_panel.dart` floor/floorplan presentation ranges | reads | CP-0 (P2) | CP-6/CP-8 |
| U8 | Assertion-level indoor content of mixed tests | per-test reads | CP-0 (P5) | CP-9 |
| U9 | dead-code candidates (`AnyplaceRadioMapRepository.clearRadioMap`, `AnyplaceFloorplanRepository.isFloorplanCached`/`clearFloorplan`, `PositionEstimate.latLng`) | reads | CP-0 (P3) | CP-6 |
| U10 | `main_shell.dart` / `profile_screen.dart` / `search_overlay.dart` MVVM status | reads | CP-0 (P2) | CP-8 |

No U item may be marked resolved without a recorded body-level finding. **Partially resolved so far:** U1, U7, U8 (see §6.1, §6.6, §7.2); remainder still UNRESOLVED.

### 11.2 A1–A7
**The exact text of A1–A7 is not available in the current planning context** and must be **recovered verbatim from the prior plan at CP-0 (register P8)**. They are intentionally **not** restated here, to avoid invention. Each must then be labelled exactly one of: *Verified by read-only evidence* · *Still unverified and blocking* · *Rejected by new findings* · *Requires explicit approval*.

**Known rejected/qualified premise (from F1–F6):** the premise that `getRouteFromCoordinates` and `composeRoute`'s indoor legs were Indoor-only removal candidates is **rejected/qualified** — see §6.1/§6.2.

---

## 12. Stop Conditions, Evidence, Acceptance, Approval Boundaries

### 12.1 Global stop conditions
Any of the following halts the workflow and requires the user's input: a source-hash drift (Gate A″) · an unexplained diff (Gates A/A′) · an illegal new path, a missing/altered pre-existing entry, a status transition, or a content-hash change (Gate B) · a Gate B parser/capture failure or any failed self-test · a truncated/contradictory CP-0 read that changes an assumption · a reachable Outdoor dependency on a proposed Indoor removal · any proposed Outdoor behavior change (CP-7B) without written approval · any weakened test assertion · any secret exposure · any diff outside an approved exact-path allowlist.

### 12.2 Final acceptance checklist
- [ ] Gate A″ source integrity · [ ] Gate B byte-safe worktree preservation · [ ] Gate A copy equivalence · [ ] Gate A′ per-checkpoint exact-path allowlists
- [ ] Outdoor routing cascade + rerouting + `floorNumber: null` preserved · [ ] gate policy (`G2` preferred; `G1`,`G3`,`G4` disabled) · [ ] KMZ graph topology + connected-component assertions (not relaxed)
- [ ] 3 assets present/unchanged · [ ] no reachable Indoor runtime dependency (§6.4) · [ ] §6.3 MVVM checks · [ ] `computeRouteCamera` contract preserved or approved migration
- [ ] identity + label + atomic channel rename · [ ] API-key confidentiality · [ ] required untracked wrappers present
- [ ] test inventory reconciled + every test/assertion dispositioned · [ ] exact commands, exit codes, counts recorded (no invented results)
- [ ] every outdoor behavior change documented + approved · [ ] both plan artifacts byte-unchanged by implementation

### 12.3 Approval boundaries
* **Technical verification ≠ plan acceptance ≠ implementation authorization.**
* CP-1 requires a **separate explicit authorization after CP-0 findings are reviewed**.
* **CP-7A may not silently become CP-7B**; CP-7B requires a **separate explicit authorization after CP-7A findings are reviewed**.
* Any necessary observable Outdoor behavior change requires its **own** written approval.
* Approval of one checkpoint/behavior change authorizes **only** that one.
* **No automatic continuation** between checkpoints.
* This document grants **no** implementation authorization; authorization must arrive as a **separate explicit message** from the user.

---

## 13. `[V2.2 ADDITION]` Cross-check against V2.1 (nothing valid lost)

| V2.1 section | V2.2 location | Status |
|---|---|---|
| §0 Change summary | §0 + revision history | Extended (A/B/C) |
| §1 Objective/Scope/DoD | §1 | Retained; DoD D11 added; user-added-buildings preserved |
| §2 Isolation | §2 | Retained; plan-artifact immutability added |
| §3 Copy/Identity/Secrets/Manifests (M1/M2/M3) | §3 | Retained; manifest distinctness rule added |
| §4 Worktree protection + Gate B | §4 | **Rewritten byte-safe (A)** |
| §5 Secrets | §5 | Retained |
| §6 Classification/MVVM/Indoor-absence | §6 | Retained; HYPOTHESIS labels added |
| §7 Test inventory | §7 | Retained |
| §8 CP-0…CP-10 incl. CP-7A/7B | §8 + §8.0 | Retained; authorization sequencing added (B) |
| §9 Gates A/A′/A″/B | §9 | Retained; **exact-path allowlists (C)** |
| §10 R1–R12 (+R13) | §10 | Retained; R14/R15 added |
| §11 U1–U10, A1–A7 | §11 | Retained |
| §12 Stop/acceptance/approval | §12 | Retained; sequencing reinforced (B) |
| Appendix Z (7-blocker map) | Appendix Y | Retained |
| — | §13 | Cross-check added |

### Appendix Y — Seven-Blocker → V2.2 Resolution Map

| Blocker | V2.2 resolution | Verification | STOP |
|---|---|---|---|
| 1 Working-tree preservation | §4: byte-safe capture + structured parser + path/status/hash comparison; exact two-artifact doc policy (§9.5) | §4.6 Gate B + self-tests §4.7 | any parse failure; missing/altered entry; illegal path |
| 2 SHA-256 manifests & gates | §3.4/§9.1: three distinct manifests; `-Force`; root-safe; sorted; hash-only; filtered ≠ source-integrity | Gates A/A′/A″ | any unexplained diff |
| 3 Outdoor/Indoor boundary | §6: responsibility/dependency/call-site; mixed files split per method | §6.1–6.6 | any Outdoor consumer of a removal |
| 4 Read-only preflight | §8 CP-0 + register P1–P8 | CP-0 artifacts | contradictory/truncated read → **stop & report** |
| 5 MVVM = responsibilities | §6.3 layer table | assertions + §6.4 | boundary violation |
| 6 Preserve Outdoor + existing work | §2/§3.3/§5/§6.2/§11 protected set; F1 shared API; CP-7B gate; Gate B | checklist + Gates | any Outdoor regression / weakened assertion / unapproved change |
| 7 Evidence + stop per checkpoint | §8 Preconditions/Actions/Evidence/Pass/Fail/Unchanged/Next/Allowlist; CP-7A/7B split | checkpoint artifacts | fail → no advance; no invented results |
