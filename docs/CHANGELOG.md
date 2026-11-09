# Changelog

This file contains notes through version 1.3.2 and upcoming changes. For version 1.3.3 and later, see the [GitHub Releases](https://github.com/ericg2/Vaulton-UI/releases).

## Unreleased

### Fixed

- You can switch folders in the Files page even when the current folder is locked.
- Encrypted folders unlock automatically when you sign in.
- Simplified the storage and folder sync screens.
- Simplified the dashboard and settings screens.
- Made folder sync options and warnings easier to understand.
- Clarified labels in transfer and backup activity screens.
- Made storage setup, backup, and restore choices easier to understand.
- Shortened backup option labels and guidance.
- Simplified storage administration wording.
- Simplified the encryption option to **Use Encryption**.
- Improved folder unlocking and recovery.
- Improved password checks and messages.
- Fixed issues with deleting folders and changing folder passwords.
- Deleting a Data Folder now permanently removes its stored files and encryption metadata; the Files page falls back to a remaining folder instead of keeping a deleted selection.
- Improved encrypted folder support for backups and syncing.
- Fixed issues when creating encrypted folders.

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
* **Auto-login flicker / hard cut**: the login form no longer flashes while the saved session is verified. A splash screen is shown instead and every screen change cross-fades.
* **List flicker**: the Files and Jobs lists now update smoothly without repeatedly showing a loading spinner.
* **Data usage not refreshing** after an upload and Back: usage and file lists refresh when they become visible again.
* **Show in Folder** now works across desktop platforms, with clearer options when a folder cannot be opened.
* Background updates stop after sign-out and restart when you sign in again.
* Login and Settings fixes, clearer error messages, and more reliable saved-password handling.
* "Queued N uploads" now shows the correct number of uploads.

### Changed
* Errors and messages are shorter and easier to read.
* Upload progress appears directly in the file list.
* Downloads show progress and actions in a single bottom sheet.

### Added
* Smoother animations throughout the app.
* More helpful tips and guidance on login, Files, Transfers, and the dashboard.
