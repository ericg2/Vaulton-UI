# Release Publishing

Vaulton releases are published manually. Do not add signing credentials, GitHub
tokens, or keystores to this repository.

## Linux

From the repository root:

```bash
chmod +x tool/publish-release.sh
./tool/publish-release.sh
```

The script checks that the working tree is clean, the current branch is
`main`, GitHub CLI is authenticated, and Android signing is configured. It
increments the patch and build numbers in `pubspec.yaml`, keeps the displayed
app version in sync, resolves dependencies, builds the signed Android APK,
creates a SHA-256 checksum, commits and pushes the version update, and creates
a GitHub Release.

GitHub CLI authentication is used for publishing. Sign in once with
`gh auth login`; the script never asks for or stores a personal access token.

Use custom Markdown release notes when needed:

```bash
./tool/publish-release.sh --notes-file ./release-notes.md
```

Or pass short notes directly:

```bash
./tool/publish-release.sh --notes "Improved file browsing and fixed sync issues."
```

Add `--yes` to skip the final confirmation prompt. Without custom notes,
GitHub generates release notes from the repository history.

## Windows

Run the PowerShell equivalent:

```powershell
.\tool\publish-release.ps1
```

You can provide custom notes with `-ReleaseNotes`.

## Android signing

Android only accepts an in-place app update when the new APK is signed with the
same private key as the installed APK. Configure signing before publishing.
Keep `android/key.properties` and its keystore private, back them up securely,
and never commit them. If the signing key is lost, existing installations
signed with it cannot receive updates over the top.

`tool/setup-signing.ps1` reuses the existing local Android debug key by default to preserve updates for installs already signed with it. That key uses Android's well-known debug-key password and is a compatibility convenience, not a recommended distribution key. For a dedicated release key, run `.\tool\setup-signing.ps1 -NewKey` from PowerShell; users with an app signed by the old key must uninstall it once before installing the new APK. Keep the generated `.vaulton` directory backed up and private.

The Linux script deliberately refuses to publish if the signing properties
file is missing or is not ignored by Git.

## Scope

`publish-release.sh` is the Linux Android publishing
entry point and currently builds the Android APK only. The PowerShell script
also builds Android. The scripts themselves build the Android APK only. After the release is published, the repository's release-triggered GitHub Actions workflows build and attach the Windows and Linux packages. Monitor those workflow runs to confirm the desktop assets were uploaded.
