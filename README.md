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

The installer configures the Vaulton APT, DNF or Zypper package source, so updates arrive through your normal package manager.

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
- **Storage:** Connect storage and manage shared space.
- **Transfers:** Track uploads and downloads.
- **Account Security:** Manage sign-in security and access tokens.
- **Server Management:** Manage users and check server status, when permitted.
- **Photo Backup:** Back up photos from Android.

Some features depend on your account permissions and the devices you use.

## Help

- [User Guide](https://github.com/ericg2/Vaulton/blob/main/docs/USER_GUIDE.md)
- [Administrator Guide](https://github.com/ericg2/Vaulton/blob/main/docs/ADMIN_GUIDE.md)
- [Troubleshooting](https://github.com/ericg2/Vaulton/blob/main/docs/TROUBLESHOOTING.md)
- [Report a Problem](https://github.com/ericg2/Vaulton-UI/issues)

See the [changelog](docs/CHANGELOG.md) for recent updates.


**Linux repository security:** The initial GitHub Pages APT and RPM repositories are served over HTTPS but are not yet signed. The installer explicitly trusts the APT repository and disables RPM/Zypper signature checks. For security-sensitive systems, use the GitHub Releases packages and verify their SHA-256 checksums until repository signing is configured.
