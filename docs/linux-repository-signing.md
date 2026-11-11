# Linux repository signing and automatic publication

Vaulton's APT, DNF, and Zypper repositories are hosted on `ericg2.github.io`. The Pages workflow no longer polls every 30 minutes. After the Linux release workflow uploads the versioned DEB and RPM assets, it sends a `repository_dispatch` event to the Pages repository.

## One-time GitHub setup

1. Generate a dedicated repository signing key on a trusted machine. The helper uses the maintainer identity Eric E. Gold and the current contact email:

   ```bash
   bash tool/setup-linux-repository-signing.sh
   ```

   The script stores the private key under `~/.vaulton/` and a base64 copy for GitHub Actions. If GitHub CLI is authenticated, it automatically uploads the public key and configures `VAULTON_REPO_SIGNING_KEY_BASE64`; otherwise it prints the exact manual steps. Back up both files securely. Do not commit the private key.

2. Upload only `~/.vaulton/vaulton-archive-keyring.gpg` to the Pages repository as `keys/vaulton-archive-keyring.gpg`.

3. Add the private-key export as the Actions secret `VAULTON_REPO_SIGNING_KEY_BASE64` in `ericg2/ericg2.github.io`. For example, with GitHub CLI:

   ```bash
   gh secret set VAULTON_REPO_SIGNING_KEY_BASE64 -R ericg2/ericg2.github.io \
     --body "$(base64 -w0 ~/.vaulton/vaulton-repository-private.asc)"
   ```

4. Create a fine-grained GitHub token restricted to the `ericg2/ericg2.github.io` repository with Contents: Read and write. Store it as `VAULTON_PAGES_TOKEN` in `ericg2/Vaulton-UI` using `gh secret set VAULTON_PAGES_TOKEN -R ericg2/Vaulton-UI`. The token is used only to send the Pages repository-dispatch event. The normal release workflow continues to use its repository-scoped `GITHUB_TOKEN` for release assets.

5. The versioned release workflow creates a draft release, builds all three platform packages, verifies that every expected asset exists, and only then publishes the release. After publication, it dispatches the Pages repository refresh. The installer refuses to configure unsigned Linux repositories. Once the signing secret and public key are present, the Pages workflow builds signed APT Release/InRelease metadata, signs the RPM package, and signs RPM repository metadata. The installer then configures APT, DNF, and Zypper signature verification.

## Security and recovery

- Keep the private key and its backup offline or in a secure password manager. Never place it in either Git repository.
- Both public-key exports are safe to publish. APT uses the binary `.gpg` keyring; DNF and Zypper use the armored `.asc` key.
- Losing the private key means future repository metadata cannot be signed as the same publisher. Existing installations will reject a replacement key until users explicitly trust the replacement.
- Android APK signing and Windows Authenticode signing are separate systems. This key signs Linux package distribution only.
- The repository refresh is event-driven after Linux package uploads; it is not triggered by every unrelated UI source edit.
