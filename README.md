<p align="center">
  <img src="assets/branding/vaulton-mark.svg" alt="Vaulton shield logo" width="112">
</p>

<h1 align="center">Vaulton</h1>
<p align="center"><strong>Your files. Your backups. Your server.</strong></p>
<p align="center">A simple way to manage your files and keep your data protected on a server you control.</p>
<p align="center">
  <a href="https://github.com/ericg2/Vaulton-UI/releases">Download the App</a> ·
  <a href="https://github.com/ericg2/Vaulton">Vaulton Server</a> ·
  <a href="https://github.com/ericg2/Vaulton-UI/issues">Get Help</a>
</p>

Vaulton gives you one place to browse files, manage backups, keep folders in sync, and check on your server. Your data stays on your own server, and you choose## Features

| Feature | What it helps you do |
|---|---|
| File management | Browse, search, upload, download, move, copy, rename, and preview files. |
| Backups | Create scheduled backups, browse saved snapshots, and restore files or folders. |
| Folder sync | Keep selected folders in sync with a storage location. |
| Storage | Connect storage locations and manage access and quotas. |
| Transfers | Track uploads and downloads, retry failed transfers, and view progress. |
| Account security | Use two-factor authentication and scoped API tokens. |
| Server management | Check server health, manage users, review jobs, and view activity when your account has permission. |
| Mobile photo backup | Back up selected photos on Android with configurable conditions. |

Vaulton only shows management features your account is allowed to use. Your server remains in control of access and permissions.


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
