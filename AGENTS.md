# Repository Guidelines

## Project Structure

`lib/` contains the Flutter application, organized into `core/`, platform adapters, and feature folders such as `auth/`, `files/`, `backups/`, and `sync/`. `test/` contains Dart tests. `web/`, `android/`, and `windows/` hold platform-specific runners and configuration. `tool/` contains project tooling. Keep generated output (`build/`, `.dart_tool/`) out of changes.

## Build, Test, and Development

- `flutter pub get` resolves dependencies from `pubspec.yaml` and `pubspec.lock`.
- `flutter run -d chrome` launches the web app in Chrome; the default API address is `http://localhost:5141` (see `lib/core/session.dart`). Start the backend from the sibling `Vaulton` repository first.
- `flutter analyze` runs Dart and Flutter static analysis using `analysis_options.yaml` and `flutter_lints`.
- `flutter test` runs the tests under `test/`.
- `dart format lib test` formats Dart source.

## Style and Testing

Use Dart’s standard formatter (two-space indentation) and follow the configured Flutter lints. Keep UI code in the relevant feature folder and shared API/session behavior in `lib/core/`. Name tests with the `_test.dart` suffix and group them by feature when practical; add focused tests for changed behavior.

## Commits and Pull Requests

Recent commits use concise imperative subjects, often naming the change directly (for example, “Polish …” or “Clarify …”). Keep commits focused. Pull requests should summarize user-visible behavior, link related issues, note tests run, and include screenshots for visual changes.

## UI Testing and Backend Data

The app calls the local backend at `http://localhost:5141` by default. For UI tests that require a clean dataset, first confirm the backend is disposable, then reset it from the sibling `Vaulton/` folder with `docker compose down --volumes`; this removes the container and named app/IPC volumes. The Compose storage bind mount defaults to `Vaulton/storage/` and is not removed by that command, so inspect it and clear its files only if they belong to the disposable test dataset. Restart with `docker compose up -d --build`, wait for the container to become healthy, check `/health/ready`, then run `flutter pub get` and `flutter run -d chrome`. Never reset production or unconfirmed data, and do not attach destructive cleanup to routine health checks or app startup. See `../Vaulton/AGENTS.md` and `../Vaulton/DEVELOPMENT.md` for backend setup.

