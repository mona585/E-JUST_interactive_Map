# Repository Guidelines

## Project Structure & Module Organization

This repository hosts the E-JUST deployment of the Anyplace indoor-navigation system. The Scala/Play API lives in `server/`: application code is in `server/app/`, configuration in `server/conf/`, database notes in `server/database/`, and Specs2 tests in `server/test/`. Static web clients are under `clients/web/`; shared JavaScript, CSS, and images belong in `clients/web/shared/`, while `anyplace_architect`, `anyplace_viewer`, and `anyplace_viewer_campus` are individual AngularJS/Grunt apps. Android modules are in `clients/android/`, with the primary app in `clients/android/Anyplace/`. Root scripts (`install.sh`, `start.sh`, `stop.sh`, `status.sh`) support Linux deployment. Treat `docker/` and `clients/deprecated/` as legacy unless a task explicitly targets them.

## Build, Test, and Development Commands

- `./install.sh` installs and configures the complete local Linux stack; use `./start.sh`, `./stop.sh`, and `./status.sh` for operations.
- `cd server && ./sbt compile` compiles the Play backend; `./sbt run` starts it on port 9000, and `./sbt test` runs backend tests. Use `./sbt dist` to build the distributable archive.
- From a web app such as `clients/web/anyplace_architect`, run `npm install`, `bower install`, then `grunt` for watch-mode development or `grunt deploy` for optimized `build/` assets.
- `cd clients/android && ./gradlew :Anyplace:assembleDebug` builds the Android client when a compatible Android SDK is installed.

## Coding Style & Naming Conventions

Follow the nearest `.editorconfig`: UTF-8, LF line endings, two-space indentation, and a 120-character maximum line length. Keep Scala types and classes in PascalCase; use camelCase for Scala/Java members and JavaScript identifiers. Match surrounding conventions for routes, JSON fields, and Angular controllers. Do not hand-edit generated web `build/` output or dependency directories.

## Testing Guidelines

Backend tests use Specs2 with Play test helpers. Put focused specs in `server/test/` and name them `*Spec.scala` (for example, `UserControllerSpec.scala`). Cover success and failure cases for changed API routes, then run `./sbt test`. There is no repository-wide coverage gate; add tests with behavior changes instead of lowering existing assertions.

## Commit & Pull Request Guidelines

Recent history follows Conventional Commit prefixes: `feat:`, `fix:`, and `chore:`; use concise imperative subjects, e.g. `fix(smas): validate empty model responses`. Target the `develop` branch per `CONTRIBUTING.md`. PRs should state the problem and solution, link the issue when applicable, list validation commands, and include screenshots for web or Android UI changes. Never commit `server/conf/app.private.conf`, credentials, runtime data, or build artifacts.
