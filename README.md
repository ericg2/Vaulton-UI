# Vaulton – Flutter client

Cross-platform client (Android · Windows · Linux · Web) for the **Vaulton API** (OpenAPI 1.0.0), written in Flutter / Material 3 with Riverpod.

## Setup

Requires **Flutter ≥ 3.47** (Dart ≥ 3.13). The Android toolchain matches what Flutter 3.47 is verified against:
Java 17, Gradle 9.3.1, Android Gradle Plugin 9.1.0, Kotlin 2.4.0 (compileSdk/targetSdk 36, minSdk 24).

```bash
flutter pub get                   # also writes android/local.properties for your machine
flutter run                       # pick your Android device
flutter build apk --release       # or: flutter build appbundle
```

`dart run tool/setup.dart` additionally creates the Windows/Linux runners if you want them
(`flutter run -d windows | linux | chrome`).

Native prerequisites: **Android** SDK platform 36 (and 37 if Gradle asks for it – newer plugins such as
`flutter_secure_storage` 11 compile against it); **Linux** `libsecret-1-dev libjsoncpp-dev`;
**Windows** Visual Studio "Desktop development with C++" (+ ATL).
Web: serve over HTTPS (or localhost) and enable CORS for your origin on the server.

To pick up newer package releases later: `flutter pub upgrade --major-versions`.

### Android notes

* `android/app/src/main/AndroidManifest.xml` declares `INTERNET` (a release build cannot reach any server without it),
  the media permissions used by photo backup, WorkManager permissions, and predictive back.
* `res/xml/network_security_config.xml` allows plain `http://` servers (typical for a home server on your LAN) and
  certificates from a private CA that you installed on the phone. Tighten it there if you only use public HTTPS.
* Release signing: create `android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`).
  Without it the release build is signed with the debug key so `flutter run --release` still works.
* `gradle.properties` keeps `android.builtInKotlin=false` (Flutter's default while plugins migrate to AGP 9), so the app
  module applies the Kotlin plugin itself. Once every plugin supports built-in Kotlin, set it to `true` and remove
  `id("org.jetbrains.kotlin.android")` from `android/app/build.gradle.kts`.
* Downloads are stored in the app's own storage (scoped storage forbids writing to arbitrary folders). Open a finished
  download from the Transfers tab to view, share or save it elsewhere. Folder upload and the custom download folder are
  desktop-only for the same reason.
* `applicationId` is still `com.example.vaulton`; change it (and the `MainActivity` package) before publishing.

## Features

| Area | What you get |
|---|---|
| Auth | Sign-in with server URL + recent-accounts list, temporary-password flow (`newPassword`), single-use refresh-token rotation (shared across isolates), tokens in Keychain/Keystore/libsecret |
| Files | Browse/search/sort, breadcrumbs, multi-select, bulk download (folders are expanded recursively), bulk move/copy (between data points, with job polling), recursive delete, rename, new folder, previews (images/text), drag-and-drop upload (desktop/web), folder upload (desktop) |
| Transfers | Uploads appear as rows in the file list with their own progress ring; downloads open a bottom sheet (progress, Open, Show in Folder). Persistent queue, parallel transfers, resumable downloads (HTTP Range), auto-retry with back-off, overwrite prompt on 409, per-item cancel/retry |
| Background (Android) | If you leave the app with transfers running they are handed to a WorkManager worker and keep going with the app closed; the UI re-attaches when you return |
| Photo backup (Android) | Google-Photos-style: periodic WorkManager job, album selection, year/month folders, Wi‑Fi / charging constraints, dedupe by HEAD + size, resumable, "back up now" |
| Folder sync (desktop) | One-way mirror of local folders into a data point on a schedule while the app is open/minimised; closing with active transfers offers "minimise" |
| Storage | Roots (all 17 connector types, forms generated from the spec), data points, repositories |
| Root sharing | Searchable user dropdown (name / user name / e-mail) that skips the owner and people who already have access, per-user quota with validation, allocation bar vs. the root's capacity, unsaved-changes guard. Without `Users.List` it falls back to typing the exact user name |
| Repositories | **Browse snapshots** like a file manager (snapshot picker, folders, search, preview), download files or whole folders, restore any file/folder to a data point; every repo card has Browse / Snapshots / Jobs / Schedules buttons |
| Recent Jobs (`Jobs.Manage`) | Snapshots (lock/unlock/delete), backup/restore/check/retention, cron schedules with preview, job history with status filters, job detail page (overview + live log with level filter/search/history paging) |
| Messages | Inbox/sent, unread filter, reply, mark read, broadcast (`Messages.Broadcast`) |
| Admin | System status, users (create/scopes/lock/reset/revoke/delete), all jobs, VFS, health events, backend logs – tabs appear only for scopes you hold |
| Theming | Material 3, Material You on Android, light/dark/system; Windows (Segoe UI, compact, small radii), Linux (GNOME-like rounding), predictive back on Android |

Scope-gated UI: `Users.List/Manage`, `Roots.Manage`, `Jobs.Manage`, `Admin.Vfs`, `Admin.Logs`, `Messages.Broadcast` (see `lib/core/scopes.dart`). The server remains the authority; 403s are shown as messages.

## Layout

```
lib/core        API client, typed endpoints (vaulton.dart), models, session, theme, shared widgets
lib/platform    dart:io vs web abstractions (local files, desktop window)
lib/background  WorkManager dispatcher (Android) + web/desktop stubs
lib/features    auth · shell · files · transfers · sync · storage · backups · messages · admin · settings
```

## Notes & limitations

* The API only deletes **empty** directories, so folder deletion/download is done client-side recursively.
* Move/copy is a server-side job; the client polls `/files/transfers/{jobId}` (3 min, then leaves it running).
* Web cannot read the filesystem in the background; downloads go through the browser and uploads are held in memory (best for small/medium files).
* Android background work is best-effort: the OS decides when periodic jobs run (minimum 15 min). Exempting the app from battery optimisation helps.
* `Content-Length` is sent for uploads; downloads resume from the existing partial file.
* iOS/macOS are not configured (no background-fetch entitlement work done).
* Query enums follow the revised spec (`Asc`/`Desc`, job `kind`/`status`, `All`/`Files`/`Directories`).
* Snapshot browse entries are expected to carry a `path` (per the endpoint description); if the server omits it the client builds `parent/name`.
* Restoring a folder from the browser writes into `<destination>/<folder name>`; a single file is restored into the destination folder. Use *Dry run* first if unsure.
