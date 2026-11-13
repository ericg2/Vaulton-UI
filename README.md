<p align="center">
  <img src="assets/branding/vaulton-mark.svg" alt="Vaulton logo" width="112">
</p>

<h1 align="center">Vaulton</h1>
<p align="center"><strong>Your files. Your backups. Your server.</strong></p>
<p align="center">Manage your files and backups on a server you control.</p>
<p align="center">
  <a href="https://ericg2.github.io">Install Vaulton</a> ·
  <a href="https://github.com/ericg2/Vaulton-UI/releases">Download Vaulton</a> ·
  <a href="https://github.com/ericg2/Vaulton">Server Setup</a> ·
  <a href="https://github.com/ericg2/Vaulton-UI/issues">Get Help</a>
</p>

Vaulton brings your files, backups, and folder syncing together in one app. Your data stays on your server, and you control who can access it.

## Getting Started

1. Set up your server using the [server setup guide](https://github.com/ericg2/Vaulton/blob/main/docs/SETUP.md).
2. [Download Vaulton](https://github.com/ericg2/Vaulton-UI/releases) for your device.
3. Open the app and enter your server address.
4. Sign in with your account.
5. Add a storage location, create a Data Folder, and set up a backup.

For help using the app, see the [user guide](https://github.com/ericg2/Vaulton/blob/main/docs/USER_GUIDE.md).

## Install Vaulton

Visit [ericg2.github.io](https://ericg2.github.io) for downloads and installation instructions.

**Linux (Debian, Ubuntu, Fedora, RHEL and openSUSE):**

```sh
curl -fsSL https://ericg2.github.io/install.sh | sh
```

Once signed Linux repositories are enabled, the installer configures the Vaulton APT, DNF or Zypper source so updates arrive through your normal package manager. Until then, use the versioned packages on the Releases page.

**Windows (PowerShell):**

```powershell
irm https://ericg2.github.io/install.ps1 | iex
```

Android users can download the signed APK from [Vaulton Releases](https://github.com/ericg2/Vaulton-UI/releases/latest).

## Downloads

Get the latest version from [Vaulton Releases](https://github.com/ericg2/Vaulton-UI/releases). Release assets include the version in their lowercase filenames and publish SHA-256 checksum files.

- **Windows:** Download and run the installer.
- **Linux:** Download the app package and installer.
- **Android:** Download and install the APK.
- **Web:** Open the hosted web app. A running Vaulton server is still required.

## What You Can Do

- **File Management:** Browse, upload, download, move, copy, and organize files.
- **Backups:** Schedule backups and restore files when needed.
- **Folder Sync:** Keep selected folders in sync.
- **Storage:** Connect private cloud accounts and manage administrator-allocated local storage.
- **Transfers:** Track uploads and downloads.
- **Account Security:** Manage sign-in security and access tokens.
- **Server Management:** Manage users and check server status, when permitted.
- **Photo Backup:** Back up photos from Android.

Some features depend on your account permissions and the devices you use.

## Help

- [User Guide](https://github.com/ericg2/Vaulton/blob/main/docs/USER_GUIDE.md)
- [Administrator Guide](https://github.com/ericg2/Vaulton/blob/main/docs/ADMIN_GUIDE.md)
- [Multi-user Storage UI](docs/MULTI_USER_STORAGE.md)
- [Troubleshooting](https://github.com/ericg2/Vaulton/blob/main/docs/TROUBLESHOOTING.md)
- [Report a Problem](https://github.com/ericg2/Vaulton-UI/issues)

See the [changelog](docs/CHANGELOG.md) for recent updates. Maintainers can follow the [release process](docs/release-process.md) to publish a complete, versioned release.


**Linux repository security:** Repository installation requires signed APT metadata, signed RPM packages, and signed RPM metadata. The one-line installer refuses to configure the repository until signing is active. See [Linux repository signing and automatic publication](docs/linux-repository-signing.md) for maintainer setup.
