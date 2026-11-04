# Changelog

This file contains curated notes through version 1.3.2 and the current unreleased changes. For version 1.3.3 and later, see the [GitHub Releases](https://github.com/ericg2/Vaulton-UI/releases), which contain the published release history.

## Unreleased

### Fixed

- Reject blank, too-short, and oversized Unicode passwords consistently with the server when creating or changing an encrypted Data Folder password.
- Clear the unused password or recovery-key field when switching Data Folder unlock methods, and enforce the API input length limits without displaying counters.
- Do not refresh the Storage list or clear point-scoped transfer state when a Data Folder deletion fails.
- Require an explicit warning before deleting an encrypted Data Folder, and explain that older server backups may still contain its key envelope.
- Explain in the recovery-key unlock flow that recovery unlock does not reset the folder password.
- Apply the same 12–1024 Unicode-character password limits in the UI, API, and Rust encryption service.
- Explain that encrypted SMB supports random-offset writes and resizing on local filesystem-backed Data Folders, while repeated small writes to large files can incur read/modify/re-encrypt overhead.
- Preserve password and recovery-key change results when IPC publication is delayed, and tell users to keep the folder unlocked while the new envelope syncs.
- Clarify that encryption applies to new empty Data Folders and existing folders require a separate file-transfer workflow.
- Share one encrypted-folder eligibility rule across immediate backup and sync flows, and allow recurring schedules to target encrypted folders without storing credentials; the folder must be unlocked when each run starts.
- Clear entered encryption credentials after rejected unlock/password-change attempts and failed folder creation.
- Default encrypted Data Folder model instances to locked unless the server explicitly reports an unlocked state.

## 1.3.2

### Fixed
* Storage limits now display two decimal places across sharing, Data Folders, Backup Vaults, and location capacity forms.
* Editing existing quotas or changing units preserves exact byte limits when the displayed value is rounded.
* Sharing includes a per-user allocation slider and a **Use Remaining** action to assign the exact remaining capacity without manually tuning decimals.

## 1.3.1

### Fixed
* Large multi-file uploads no longer rebuild and persist the entire transfer queue for every file.
* Browser uploads load file bytes only when a transfer starts, limiting memory use to concurrent uploads.
* Large uploads show a combined progress row instead of building thousands of file rows at once.

## 1.3.0

### Fixed
* **Auto-login flicker / hard cut**: the login form no longer flashes while the saved session is verified. A splash
  screen is shown instead (minimum ~0.9 s) and every screen change cross-fades.
* **List flicker**: the Files and Jobs lists refreshed with a full reload (spinner) every few seconds. They now update
  silently in place, and the poller leaves your list alone if you have scrolled past the first page.
* **Data usage not refreshing** after an upload and Back: the transfer manager now announces finished uploads itself
  (even if the Files screen is closed), and the Dashboard, Storage and file lists reload as soon as they become visible again.
* **Show in Folder** did nothing (it tried to "open" a directory). Windows now selects the file in Explorer, macOS uses
  `open -R`, Linux `xdg-open`. If the OS cannot open the folder (typical on Android app storage) a sheet shows the path
  with Copy / Open File. The button is only shown for finished downloads.
* Pollers (unread count, server info) kept running after sign-out; they now stop and restart per account.
* Login: text controllers were never disposed; 401 shows a clear message; saved-password write no longer depends on a
  widget that is being replaced.
* Settings: About showed 1.1.0; avatar crashed on an empty user name.
* "Queued N uploads" counted duplicates that were not actually queued.

### Changed
* Errors and messages are compact floating toasts with an icon (auto-dismiss, max 3 lines) instead of tall blocks.
* Uploads are shown **in the file list** (spinning progress ring per file, one grouped row per folder) instead of a
  floating panel; failures stay with Retry / Overwrite / Dismiss.
* Downloads open a **bottom sheet** with live progress, Cancel/Retry, Open and Show in Folder.

### Added
* Animations: staggered login entrance, breathing logo, animated error / password-change sections, tab fade,
  dashboard staggered cards, counting stats, animated usage bars.
* Help: server-address hint, "Need help?" sheet on login, dismissible tips (Files, Transfers, More), empty-state hints
  (files, data points, repositories, roots), friendlier connection-error text, get-started card on the dashboard.
