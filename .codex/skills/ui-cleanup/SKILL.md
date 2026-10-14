---
name: ui-cleanup
description: Audit and improve an existing application's UI for consistency, usability, responsive layouts, and verified behavior across platforms. Use when asked to clean up, polish, fix visual issues, or make an existing UI easier to use.
---

# UI Cleanup

Use this skill to make concrete, user-visible improvements to an existing app while preserving its architecture and behavior contracts.

## Workflow

1. Read repository guidance (`AGENTS.md`, relevant feature documentation, and local component/theme conventions). Inspect the current changes and avoid overwriting unrelated user work.
2. Map the affected flow before editing. Identify entry points, related screens, shared components, loading/empty/success/failure states, data mutations, and platform-specific code. Reproduce the reported problem when possible.
3. Inspect the design system and adjacent screens. Reuse established spacing, typography, color, shape, icons, and interaction patterns. Avoid broad redesigns unless the user asks for them.
4. Fix issues in small, focused edits. Keep navigation/state stable through resize and rebuild, preserve API and persisted-data contracts, and make unavailable actions explicit. For destructive operations, make scope clear and require confirmation when needed.
5. Review every affected state and related copy. Use concise, grammatical text with consistent capitalization and terminology. Avoid extra confirmation dialogs for routine actions.
6. Validate multiple sizes and conditions. At minimum, cover a narrow phone (~320 logical pixels), a typical phone (~390), tablet (~768), and desktop (~1280), adjusting for the actual product. Check overflow, scrolling, clipping, safe areas, keyboard behavior, long labels, text scaling, and modal sizing. Test empty and populated lists and active/progress/error states where applicable.
7. Run focused tests and the relevant broader checks. Use real service integration tests only when the service is available and the dataset is confirmed disposable or isolated. Never reset, delete, or overwrite uncertain user data merely to simplify testing.
8. Inspect the running UI in the browser or native app when visual claims matter. A passing test or successful platform build does not prove that the rendered screen looks correct. Follow any platform automation skill before controlling an app.
9. Summarize the changes, commands and scenarios actually verified, remaining analyzer/build issues, and platform inspection limits. Never overstate validation.

## Flutter Notes

- Prefer targeted Dart formatting; formatting an entire legacy file can create unrelated diff churn.
- Use responsive constraints (`LayoutBuilder`, wrapping, scrolling) instead of fixed action rows that assume desktop width.
- Long dropdown content should not force a narrow parent to overflow; check `isExpanded` and dialog/list constraints.
- Progress indicators should use determinate values when the operation reports reliable progress. Keep cancellation available when safe.
- Widget tests must provide the app's required provider/dependency scope and should assert `tester.takeException()` after pumping layouts at each target size.
- Test named platform behavior separately. Web often lacks native file access or background execution; disable unsupported controls and give a short explanation rather than presenting a dead end.
- For backend-backed checks, use an opt-in test gated by environment configuration, isolated test records/files, and cleanup scoped only to data created by that test. Never embed credentials in source or logs.

## Completion Checklist

- [ ] The affected flow is consistent with neighboring UI and clearly communicates what will happen.
- [ ] Loading, empty, unavailable, error, and active states are handled where relevant.
- [ ] Narrow and wide layouts avoid overflow, clipping, and inaccessible controls.
- [ ] Platform limitations are handled truthfully.
- [ ] Focused tests and relevant checks were run and their results recorded accurately.
- [ ] The diff contains only intentional changes and preserves user data/API contracts.
