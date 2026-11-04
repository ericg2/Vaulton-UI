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
- Avoid visually overloaded screens. Give each screen a clear primary purpose and keep cards focused on the information and actions users need at a glance. Do not stack many raw-text rows, metadata labels, helper paragraphs, or secondary details under every card; prioritize the key value/status and a small number of relevant actions.
- Use visual hierarchy and progressive disclosure for secondary or advanced information. Move lengthy diagnostics, technical details, and less-used settings into a dedicated detail screen, expandable section, or clearly labeled secondary view instead of making the main screen a wall of text. Keep raw technical output out of user-facing summaries unless the user explicitly needs it.
- Review every card and screen for information density: remove repeated labels, redundant descriptions, and decorative metadata; group related values; use concise summaries; and make additional detail available on demand. Do not solve clutter by hiding information users need to make a safe decision.
- Keep authentication flows compact and focused. For example, changing a password from the login screen should normally navigate to a dedicated Change Password screen (or a similarly focused full-screen flow) rather than expanding a large form inline and making the login screen excessively tall. Preserve a clear way to return to login and handle validation, loading, and errors within that flow.

## Branding, Logos, and Platform Assets

- Keep Vaulton's visual identity consistent throughout the app and across Windows, Android, web, and any other supported platform. Use the established, approved Vaulton logo and brand assets from the project; do not redraw, approximate, substitute, or introduce a different logo without an explicit design decision.
- Audit every place the brand appears, including the login and other app screens, navigation, splash/loading screens, app launcher icons, window/taskbar icons, installers, browser favicon, and platform metadata where applicable. Ensure the correct asset is configured and actually included in each platform's packaged output.
- Use appropriate variants and sizes for each context (full logo/wordmark versus compact app icon). Preserve the logo's proportions, clear space, legibility, and intended colors; never stretch, crop, recolor, or place it on a background that makes it difficult to see.
- Check logo visibility in both light and dark themes and on different background colors. Provide suitable approved variants or backgrounds where necessary rather than applying ad hoc filters or changing the source artwork.
- Centralize brand assets and references where practical so screens and platform configurations do not drift or point to duplicate, outdated, or missing files. Follow the platform's asset-generation requirements and keep generated icon resources in sync with the source asset.
- Verify branding on actual supported platform outputs when practical, not just in source code or a successful compile. Check that icons survive release packaging/tree-shaking and appear correctly in installed/running apps. Report any platform that could not be visually verified; do not claim universal support based only on one platform's build.
- Keep brand colors, typography, icon style, and component styling coherent across screens. Reuse shared theme tokens and components instead of introducing one-off colors or visual treatments. Branding should feel consistent without making every screen visually repetitive or overly decorated.

## Navigation and Discoverability

- Make core features and common actions easy to find. Do not bury important functionality several levels deep in nested menus, overflow menus, or unrelated settings pages.
- Use clear, predictable navigation with a shallow information hierarchy. Prefer a direct destination, visible tab, clearly named section, or contextual action over making users guess where a feature lives.
- Put frequently used actions where users naturally need them, close to the relevant content or workflow. Keep rare, advanced, or destructive actions secondary without making routine tasks difficult to reach.
- Use menus for genuinely secondary or occasional actions, not as the default hiding place for major features. Avoid excessive nesting and avoid duplicating the same action in multiple places without a clear usability reason.
- Keep navigation labels understandable to inexperienced users. Group related features under intuitive names, make the current location clear, and provide a straightforward way back. Do not make users learn internal technical terminology to find ordinary tasks.
- Balance discoverability with visual simplicity: make important destinations visible without filling every screen with buttons. Review common user journeys and check that key tasks can be reached in a small, predictable number of steps.

## Task-Specific Screens and Workflows

- Prefer purpose-built, task-specific screens and interaction flows over generic placeholder forms. Do not reduce a meaningful product action to a lone text box, a few unstructured fields, or a bare submit button when the task has domain-specific choices, configuration, review, or lifecycle steps.
- Design each action around what the user is trying to accomplish. Use appropriate controls such as permission checklists, scope selectors, toggles, searchable lists, summaries, validation, and review/confirmation steps when they make the task clearer and safer. Explain options in plain language and show the consequences of the selected choices.
- For example, API token creation should be a dedicated, understandable flow: let the user name the token, explicitly choose its permissions/scopes, explain what those permissions allow, apply least-privilege defaults, review the selection, and then create the token. Present the generated secret clearly with a copy action and a warning that it may only be shown once, where that matches backend behavior. Do not substitute a generic token text box for this workflow.
- Keep these experiences focused rather than adding complexity for its own sake. A simple form is appropriate when the task genuinely needs only a small amount of information; use richer screens and controls when the underlying action warrants them. Reuse existing design-system components and maintain responsive, accessible layouts.

## Safety and Data Integrity

- Treat deletion, restore, overwrite, reset, and cleanup operations as consequential. Make the scope clear and require confirmation when needed.
- Never call data-deletion or reset endpoints, delete test data, or run destructive Docker cleanup merely to make a test environment easier to start. First establish that the target is disposable and the requested operation is necessary; ask before proceeding when ownership or data safety is uncertain.
- Never reset production or unconfirmed data. Do not attach destructive cleanup to routine health checks, app startup, or ordinary test runs.
- Preserve user data and existing API contracts. Do not silently change backend behavior, protocol definitions, persisted formats, identifiers, or defaults as part of an unrelated UI task.
- Handle authentication, session expiration, unavailable servers, and network errors explicitly. Do not expose credentials, tokens, or sensitive request data in logs or user-facing messages.

## Commits and Pull Requests

Recent commits use concise imperative subjects, often naming the change directly (for example, “Polish …” or “Clarify …”). Keep commits focused. Pull requests should summarize user-visible behavior, link related issues, note tests run, and include screenshots for visual changes.

## Testing and Backend Coordination

Follow the sibling backend repository's [TESTING.md](../Vaulton/TESTING.md) for test design, organization, isolation, and release evidence. Organize Flutter tests by feature and layer under `test/`, separating pure unit tests, widget tests, and end-to-end workflows. Mocked API/widget tests do not replace integration tests against the real backend.

The app uses `http://localhost:5141` by default. For UI tests requiring a clean backend dataset, first confirm that the target is disposable and obtain authorization before resetting it. If explicitly approved, follow the backend procedure: `docker compose down --volumes` removes named app/IPC volumes but does not remove the configured storage bind mount. Inspect that mount and clear only files confirmed to belong to the disposable test dataset. Rebuild with `docker compose up -d --build`, wait for health, verify `/health/ready`, then run Flutter tests or the app. Never reset production or unconfirmed data; do not automate destructive cleanup.

For Data Folder encryption, follow [the backend encryption requirements](../Vaulton/docs/ENCRYPTION.md). Cover every UI state and user-facing action, including encrypted/plain parity, locked/unlocked behavior, errors, cancellation, stale state, server switching, and credential clearing. Keep the UI honest about backend capability and unlock requirements. Do not duplicate the backend threat model or operation inventory here.
