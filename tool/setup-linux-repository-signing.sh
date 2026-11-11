#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

KEY_HOME="${HOME}/.vaulton/repository-signing-gnupg"
OUT="${HOME}/.vaulton"
UID_TEXT="Eric E. Gold <littlelettere@gmail.com>"

command -v gpg >/dev/null 2>&1 || {
  echo "GnuPG is required. On Fedora: sudo dnf install gnupg2" >&2
  exit 1
}

mkdir -p "$KEY_HOME" "$OUT"
chmod 700 "$KEY_HOME" "$OUT"
export GNUPGHOME="$KEY_HOME"

if gpg --batch --with-colons --list-secret-keys 2>/dev/null | grep -q '^fpr:'; then
  echo "A signing key already exists in $KEY_HOME; refusing to replace it." >&2
  exit 1
fi

echo "Creating a dedicated RSA-4096 signing key for Vaulton's Linux repositories."
echo "This key is separate from Android app signing and Windows code signing."
gpg --batch --pinentry-mode loopback --passphrase '' \
  --quick-generate-key "$UID_TEXT" rsa4096 sign 10y

FINGERPRINT="$(gpg --batch --with-colons --list-secret-keys | awk -F: '$1 == "fpr" { print $10; exit }')"
[[ "$FINGERPRINT" =~ ^[A-F0-9]{40}$ ]] || {
  echo "Could not determine the generated signing-key fingerprint." >&2
  exit 1
}

gpg --batch --export "$FINGERPRINT" > "$OUT/vaulton-archive-keyring.gpg"
gpg --batch --armor --export-secret-keys "$FINGERPRINT" > "$OUT/vaulton-repository-private.asc"
chmod 600 "$OUT/vaulton-repository-private.asc"
chmod 644 "$OUT/vaulton-archive-keyring.gpg"

echo
echo "Signing key created."
echo "Fingerprint: $FINGERPRINT"
echo "Public key:  $OUT/vaulton-archive-keyring.gpg"
echo "Private key: $OUT/vaulton-repository-private.asc"
echo
echo "Add the PUBLIC key to ericg2.github.io at keys/vaulton-archive-keyring.gpg."
echo "Never commit or upload the private key."
echo
echo "Create the GitHub Actions secret VAULTON_REPO_SIGNING_KEY_BASE64"
echo "in ericg2/ericg2.github.io using this value:"
base64 -w0 "$OUT/vaulton-repository-private.asc"
echo
echo
echo "Back up both key files securely. Losing the private key prevents signing"
echo "future repository metadata with the same trusted identity."
