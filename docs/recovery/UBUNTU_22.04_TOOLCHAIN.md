# Ubuntu 22.04 Toolchain Contract

This is the recovery target for production and private staging. Windows is an
investigation/development host only; do not run the production service,
systemd unit, Nginx, MongoDB, or tiler there.

## Pinned baseline

| Component | Required version | Evidence in repository |
| --- | --- | --- |
| OS | Ubuntu Server 22.04 LTS (Jammy), amd64 | D-01 decision |
| Backend JDK | OpenJDK 17 | Play 2.8.8; Android build also requires JDK 17 |
| SBT / Scala / Play | 1.5.8 / 2.13.6 / 2.8.8 | `server/project/build.properties`, `server/build.sbt` |
| MongoDB tools | MongoDB Community 6.0.x and `mongosh` | initial co-located baseline; runtime hardening is Phase 2 |
| Node / npm | Node.js 22 LTS / npm 10 | committed npm lockfiles use lockfile v3 |
| Web tools | Grunt CLI 1.5.0; Bower 1.8.14 | legacy AngularJS/Grunt applications |
| Tiler | Python 3.10+, ImageMagick 6, AdvanceCOMP (`advpng`) | `server/anyplace_tiler/` |
| Android (Linux build host) | Gradle 6.5.1, AGP 4.0.2, SDK platform API 29, Build-Tools 29.0.2 | `clients/android-new/` (merged phase-7-8 lineage) |

The Node 22 line is intentionally used for the legacy web build because it is
currently supported; package resolution must always use `npm ci`, never
unlocked `npm install`. Do not substitute a newer major version without a
separate compatibility test.

The backend pins OpenJDK 17. The merged `clients/android-new` tree uses the
Gradle 6.5.1 wrapper, which cannot run on JDK 17; Android builds therefore
additionally require a local OpenJDK 11 (`sudo apt install openjdk-11-jdk`)
selected only for Gradle invocations (for example `JAVA_HOME` or
`org.gradle.java.home`). The original contract's Gradle 7.2 / AGP 7.1.3 /
API 31 pin belonged to a lineage that was replaced by the phase-7-8 merge and
is no longer authoritative for this branch.

## VM preparation

Provision a clean Ubuntu 22.04 VM, then install the OS packages:

```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg git unzip zip make g++ \
  openjdk-17-jdk python3 imagemagick advancecomp netcat-openbsd
```

Install Node 22 from the university-approved Node.js mirror and MongoDB 6.0
from the university-approved MongoDB package mirror. Record the exact package
revisions in the VM build record; neither is committed as a binary dependency.
Install the legacy web CLIs once per build host:

```bash
sudo npm install --global grunt-cli@1.5.0 bower@1.8.14
```

Clone with submodules before any Android build. The Android modules depend on
`clients/android-new/lib-android` and `clients/core/lib`:

```bash
git submodule update --init --recursive
```

Those submodules use SSH remotes. Access to the E-JUST/delegated GitHub keys is
an external dependency; do not replace them with copied source or public forks.

## Offline preflight

From the repository root on the Ubuntu VM, run:

```bash
scripts/verify-ubuntu-toolchain.sh
scripts/verify-ubuntu-toolchain.sh --with-android
```

The first command validates the backend, web, and tiler build tools without
starting services. The Android check also requires `ANDROID_SDK_ROOT` and the
SDK platform/build-tools above. MongoDB listener/authentication validation is
deliberately deferred to Phase 2.
