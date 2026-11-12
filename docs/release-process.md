# Vaulton release process

Releases are version-driven. To publish a new version:

1. Update the version and build number in `pubspec.yaml`.
2. Commit and push the version change to `main`.
3. The `Publish versioned Vaulton release` workflow runs Flutter dependency resolution, static analysis, and tests.
4. If validation passes, it creates a draft GitHub release for the new version.
5. It dispatches the Linux, Windows, and Android packaging workflows and waits for each to finish successfully.
6. It verifies the expected versioned, lowercase assets and SHA-256 checksum files are attached.
7. Only after all required packages are present does it publish the release.
8. It sends a repository-dispatch event to `ericg2/ericg2.github.io`, which rebuilds the APT, DNF, and Zypper repositories from the newly published DEB and RPM packages.

The draft-release stage is intentional: the public latest-release API and in-app update checks do not see an incomplete release while packages are being built. If a platform build fails, rerun the workflow with the existing draft tag; it reuses the draft and rebuilds any platform whose complete package/checksum set is missing.

## Required repository secrets

- `VAULTON_PAGES_TOKEN` in `ericg2/Vaulton-UI` (optional): fine-grained token restricted to `ericg2/ericg2.github.io`, with Contents: Read and write. It dispatches an immediate Pages refresh after the complete release is published. Without it, the Pages workflow checks for new releases every 15 minutes.
- `VAULTON_REPO_SIGNING_KEY_BASE64` in `ericg2/ericg2.github.io`: base64-encoded ASCII-armored GPG private key used to sign APT Release metadata, RPM packages, and RPM repository metadata.

The public keys must be committed to `ericg2/ericg2.github.io/keys/vaulton-archive-keyring.gpg` (APT) and `ericg2/ericg2.github.io/keys/vaulton-archive-key.asc` (RPM). Use `tool/setup-linux-repository-signing.sh` to generate the key and configure the public key and signing secret with GitHub CLI.

Android release signing remains backed by the existing `VAULTON_KEYSTORE_BASE64`, `VAULTON_KEYSTORE_PASSWORD`, `VAULTON_KEY_PASSWORD`, and `VAULTON_KEY_ALIAS` secrets.

Do not commit private signing material, keystores, API tokens, or generated local signing configuration.
