# Repository Guidelines

## Project Structure

`lib/` contains the Flutter application, organized into `core/`, platform adapters, and feature folders such as `auth/`, `files/`, `backups/`, and `sync/`. `test/` contains Dart tests. `web/`, `android/`, and `windows/` hold platform-specific runners and configuration. `tool/` contains project tooling. Keep generated output (`build/`, `.dart_tool/`) out of changes.

## Build, Test, and Development

- `flutter pub get` resolves dependencies from `pubspec.yaml` and `pubspec.lock`.
- `flutter run -d chrome` launches the web app in Chrome; the default API address is `http://localhost:5141` (see `lib/core/session.dart`). Start the backend from the sibling `Vaulton` repository first.
- `flutter analyze` runs Dart and Flutter static analysis using `analysis_options.yaml` and `flutter_lints`.
- `flutter test` runs the tests under `test/`.
- `dart format lib test` formats Dart source.
- Run the relevant checks after changes and report exactly which commands succeeded, failed, or could not be run. Never claim that a build, test, install, or runtime behavior was verified unless it was actually verified.

### Verified Sync and Platform Behavior

- Folder Sync requires access to a local filesystem directory through the platform file picker. Flutter Web cannot provide the native directory access required by this feature, so do not offer a working-looking Add Folder, Sync Now, Preview, Settings, or enabled-profile toggle in a browser. Explain briefly that local folder sync is available in the desktop and mobile apps.
- Native folder sync runs on supported desktop/mobile platforms. Background sync is platform-dependent; inspect `backgroundSupported` and the relevant adapters before changing behavior. A foreground sync should review its plan before applying changes, and mirror deletion must remain explicit and accurately described.
- Keep sync phases understandable: scan/plan, transfer, completion, and failure. Show determinate byte progress when known, permit safe cancellation, and never hide the source, destination, or delete scope.
- Sync profile cards need responsive actions. At narrow widths, wrap actions instead of forcing a single row; expand long dropdowns and ensure dialogs scroll within the available height.
- The Sync layout suite covers 320×568, 390×844, 768×900, and 1280×900 logical-pixel viewports, as well as an active transfer at 320×700. Extend this coverage when responsive behavior changes.
- `test/features/sync/sync_live_backend_test.dart` is an opt-in integration test. It requires `VAULTON_TEST_PASSWORD` and `VAULTON_TEST_POINT_ID`, creates isolated temporary source files, and exercises plan/apply against a running local Vaulton API. Use only a confirmed disposable test backend. The ordinary `flutter test` intentionally skips it when credentials are absent.
- A clean widget test of the root app needs `ProviderScope` overrides for `prefsProvider` and `sessionProvider`; directly pumping `VaultonApp` without providers is not a valid smoke test.
- Windows can be build-verified with `flutter build windows`; widget tests can check desktop-size layouts. A successful build does not establish native visual correctness, so inspect the running native window when Windows visual QA is requested and computer-use access is available.
- During this task, actual browser inspection showed the web Sync page. Native Windows UI automation was not available in that run; only its Windows release build and responsive widget coverage were verified. Do not treat this historical limitation as a current tool limitation without checking.

### Responsive UI Review

- For UI fixes, inspect the whole flow and its loading, empty, success, unavailable, and failure states, not just the main screen.
- Exercise small phone width (320 logical pixels), common mobile width (390), tablet width (768), and desktop width (1280); check text scaling where the layout contains dense controls.
- In Flutter widget tests, use `tester.view.physicalSize` and `devicePixelRatio` deliberately, settle animations, and fail on `tester.takeException()` so RenderFlex overflows are caught.
- Use runtime browser/native inspection for visual issues that widget structure alone cannot prove. If inspecting Windows, first read and follow the `computer-use` skill workflow.
- Re-run `flutter test`, `flutter analyze`, and the relevant platform build. Report pre-existing analyzer findings separately from issues introduced by the change. Do not claim platform visual verification from a compile or widget test alone.

## Style and Testing

Use Dart’s standard formatter (two-space indentation) and follow the configured Flutter lints. Keep UI code in the relevant feature folder and shared API/session behavior in `lib/core/`. Name tests with the `_test.dart` suffix and group them by feature when practical; add focused tests for changed behavior.

Prefer small, focused diffs. Preserve the existing architecture, naming, and established patterns unless the task requires a change. Avoid unrelated refactors, duplicate abstractions, speculative fixes, and unnecessary comments. Do not replace whole files when a targeted change is sufficient. Do not modify generated files unless the task specifically requires it.

## Grammar, Capitalization, and UI Copy

Consistently apply these rules to every user-facing string, including buttons, page and section titles, dialogs, menus, tabs, tooltips, notifications, validation messages, empty states, and errors:

- Use **Title Case** for button labels, page titles, section headings, dialog titles, and other short UI labels. Capitalize the important words consistently; do not randomly mix sentence case and Title Case within the same category.
- Use **sentence case** for explanatory text, descriptions, helper text, notifications written as sentences, and error messages. Start sentences with a capital letter and use normal punctuation.
- Keep copy concise, professional, clear, and natural. Prefer familiar wording over unnecessary technical language.
- Use correct grammar, spelling, punctuation, and singular/plural forms. Make counts agree with their nouns and use clear articles and verb agreement.
- Use complete sentences with punctuation when the text is a sentence. Short labels do not need an added period.
- Preserve established product terms and technical identifiers, including Vaulton, Snapshot ID, Data Point ID, Repository Point, and other domain-specific names. Do not alter an identifier’s value or casing for stylistic reasons.
- Check related screens and states together when changing copy so the same concept is described consistently.
- Avoid redundant wording, awkward phrases, overly long labels, and messages that merely repeat the title or button that caused them.
- Do not add unnecessary confirmation popups or extra actions such as a “Clear Filters” popup. Keep interactions direct unless confirmation is needed to prevent a meaningful destructive or irreversible action.
- Examples of the preferred style: “No data folders yet.” for an empty-state sentence; “Select All” for a button; “Waking up…” for an in-progress status. Treat these as examples of the casing and tone, not strings to use in unrelated contexts.

## UI and Interaction Principles

- Keep spacing, alignment, typography, colors, component shapes, and interaction patterns consistent across the app. Reuse existing shared components and theme conventions where practical.
- Make layouts work on Windows, Android, and other supported targets. Check narrow and wide layouts, scrolling, clipping, keyboard behavior, and safe areas where relevant.
- Avoid clipped titles, buttons, settings, and menus. Scrollbars should sit at the expected edge of the scrollable content and should not cover or misalign the UI.
- Preserve navigation and page state across window resizing and ordinary rebuilds. Do not unexpectedly reset the dashboard or the current view. On mobile, back navigation should return to the expected parent screen.
- Keep related tabs, filters, chips, and actions aligned and consistent. Where a screen already has established scrolling or animation behavior, reuse it instead of introducing a different pattern without a reason.
- Provide clear loading, empty, success, unavailable, and failure states. Disable actions that cannot currently succeed and explain why when helpful.
- Progress UI should be stable and informative. Avoid full-screen progress flashes, unnecessary transitions, and progress indicators that obscure the normal screen for a brief operation. For long-running work, show meaningful status and progress; support cancellation where the operation can safely be cancelled.
- Use human-readable byte units and existing unit-selection conventions. Do not add “Exact bytes” labels everywhere when a normal unit display or unit selector is more appropriate.
- Preserve existing icons and visual meaning when adding controls. Do not replace a file or folder icon with a generic control icon.
- Hide “Show More” when there is nothing more to show. Handle empty lists and missing related records explicitly rather than showing broken or misleading actions.
- Use consistent status wording and styling. Snapshot lock status should be clearly identified as “Locked”; unavailable or missing snapshots must not offer a View Snapshot action that cannot work.
- Keep Snapshot IDs stable and visible where the snapshot UI expects them. Never change an ID as a side effect of locking, unlocking, refreshing, or displaying a snapshot.
- Login and server wake-up flows must provide truthful feedback. Check whether the server is reachable before requesting a wake-up when appropriate, avoid repeatedly sending wake requests, stop or recover cleanly after authentication failures, and never leave the UI stuck indefinitely on “Waking up…”.
- Sync should clearly communicate source and destination, scan and transfer phases, cancellation, and errors. Preserve the configured mirror behavior, including the user's delete option, and warn clearly when selecting a root could affect the entire point.
- Keep UI strings short enough to fit supported layouts. Verify that text scaling, localization-ready layouts, and small screens do not cause avoidable overflow.

## Safety and Data Integrity

- Treat deletion, restore, overwrite, reset, and cleanup operations as consequential. Make the scope clear and require confirmation when needed.
- Never call data-deletion or reset endpoints, delete test data, or run destructive Docker cleanup merely to make a test environment easier to start. First establish that the target is disposable and the requested operation is necessary; ask before proceeding when ownership or data safety is uncertain.
- Never reset production or unconfirmed data. Do not attach destructive cleanup to routine health checks, app startup, or ordinary test runs.
- Preserve user data and existing API contracts. Do not silently change backend behavior, protocol definitions, persisted formats, identifiers, or defaults as part of an unrelated UI task.
- Handle authentication, session expiration, unavailable servers, and network errors explicitly. Do not expose credentials, tokens, or sensitive request data in logs or user-facing messages.

## Commits and Pull Requests

Recent commits use concise imperative subjects, often naming the change directly (for example, “Polish …” or “Clarify …”). Keep commits focused. Pull requests should summarize user-visible behavior, link related issues, note tests run, and include screenshots for visual changes.

## UI Testing and Backend Data

The app calls the local backend at `http://localhost:5141` by default. For UI tests that require a clean dataset, first confirm the backend is disposable and obtain authorization before resetting it. If a reset is explicitly approved, use the procedure documented by the backend repository; `docker compose down --volumes` removes the container and named app/IPC volumes. The Compose storage bind mount defaults to `Vaulton/storage/` and is not removed by that command, so inspect it and clear its files only if they belong to the disposable test dataset. Restart with `docker compose up -d --build`, wait for the container to become healthy, check `/health/ready`, then run `flutter pub get` and `flutter run -d chrome`. Never reset production or unconfirmed data, and do not attach destructive cleanup to routine health checks or app startup. See `../Vaulton/AGENTS.md` and `../Vaulton/DEVELOPMENT.md` for backend setup.
