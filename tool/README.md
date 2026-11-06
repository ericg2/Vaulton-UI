# Release Publishing

Vaulton releases are published manually. Do not add signing credentials, GitHub
tokens, or keystores to this repository.

## Linux

Configure Android signing once from the repository root:

```bash
chmod +x tool/setup-signing.sh
./tool/setup-signing.sh
```

By default, setup reuses `~/.android/debug.keystore` when present to preserve
the signature of existing debug-signed installs. To generate a dedicated
production key instead, run `./tool/setup-signing.sh --new-key`. Switching
keys means existing installations signed with the previous key must be
uninstalled once before installing the new APK.

Then publish:

```bash
chmod +x tool/publish-release.sh
./tool/publish-release.sh
```

The publishing script checks that the working tree is clean, the current branch
is `main`, GitHub CLI is authenticated, and Android signing is configured. It
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

Run the PowerShell signing setup once:

```powershell
.\tool\setup-signing.ps1
```

Then publish:

```powershell
.\tool\publish-release.ps1
```

You can provide custom notes with `-ReleaseNotes`.

## Android signing and key backup

Android only accepts an in-place app update when the new APK is signed with the
same private key as the installed APK. The signing setup writes the private
keystore outside the repository and Gradle settings inside the ignored Android
directory. Never commit either file.

On Linux, the exact default locations are:

- Private keystore: `~/.vaulton/vaulton-release.jks`
- Signing passwords and alias: `android/key.properties` in the repository
- Permissions: `.vaulton` is mode `700`; the keystore and properties file
  are mode `600`

On Windows, the keystore is `%USERPROFILE%\.vaulton\vaulton-release.jks`,
and the properties file is `android/key.properties`.

Back up BOTH the keystore and `android/key.properties` somewhere secure.
The keystore alone is not enough because the passwords and alias are in the
properties file. If either is lost, existing installations signed with that
key cannot receive updates over the top. Do not upload either file to GitHub.

The Linux publisher refuses to publish if `android/key.properties` is missing
or is not ignored by Git.

## Scope

The release scripts build the Android APK only. After the release is published,
the repository's release-triggered GitHub Actions workflows build and attach
the Windows and Linux packages. Monitor those workflow runs to confirm the
desktop assets were uploaded.
