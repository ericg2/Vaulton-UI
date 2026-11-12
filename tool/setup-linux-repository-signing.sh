#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

KEY_HOME="${HOME}/.vaulton/repository-signing-gnupg"
OUT="${HOME}/.vaulton"
PUBLIC_KEY="$OUT/vaulton-archive-keyring.gpg"
RPM_PUBLIC_KEY="$OUT/vaulton-archive-key.asc"
PRIVATE_KEY="$OUT/vaulton-repository-private.asc"
PRIVATE_KEY_BASE64="$OUT/vaulton-repository-private.asc.base64"
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

gpg --batch --export "$FINGERPRINT" > "$PUBLIC_KEY"
gpg --batch --armor --export "$FINGERPRINT" > "$RPM_PUBLIC_KEY"
gpg --batch --armor --export-secret-keys "$FINGERPRINT" > "$PRIVATE_KEY"
base64 -w0 "$PRIVATE_KEY" > "$PRIVATE_KEY_BASE64"
chmod 600 "$PRIVATE_KEY" "$PRIVATE_KEY_BASE64"
chmod 644 "$PUBLIC_KEY" "$RPM_PUBLIC_KEY"

echo
echo "Signing key created."
echo "Fingerprint: $FINGERPRINT"
echo "APT public key: $PUBLIC_KEY"
echo "RPM public key: $RPM_PUBLIC_KEY"
echo "Private key: $PRIVATE_KEY"
echo "Secret input: $PRIVATE_KEY_BASE64"
echo
echo "The private key is never committed to either repository."

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  echo "GitHub CLI authentication found. Publishing the public key and configuring its Actions secret..."
  gh api --method PUT repos/ericg2/ericg2.github.io/contents/keys/vaulton-archive-keyring.gpg \
    -f message="Publish Vaulton Linux repository signing public key" \
    -f branch=main \
    -f content="$(base64 -w0 "$PUBLIC_KEY")" >/dev/null
  gh api --method PUT repos/ericg2/ericg2.github.io/contents/keys/vaulton-archive-key.asc \
    -f message="Publish Vaulton Linux RPM signing public key" \
    -f branch=main \
    -f content="$(base64 -w0 "$RPM_PUBLIC_KEY")" >/dev/null
  gh secret set VAULTON_REPO_SIGNING_KEY_BASE64 \
    -R ericg2/ericg2.github.io < "$PRIVATE_KEY_BASE64"
  echo "Public key and repository signing secret configured."
else
  echo "GitHub CLI is not authenticated. Configure these manually:"
  echo "  1. Upload $PUBLIC_KEY as keys/vaulton-archive-keyring.gpg and $RPM_PUBLIC_KEY as keys/vaulton-archive-key.asc"
  echo "  2. Run: gh secret set VAULTON_REPO_SIGNING_KEY_BASE64 -R ericg2/ericg2.github.io < $PRIVATE_KEY_BASE64"
  echo "  3. Dispatch the Publish Vaulton installation site workflow in ericg2/ericg2.github.io."
fi

echo
echo "Automatic Linux repository refresh requires VAULTON_PAGES_TOKEN in ericg2/Vaulton-UI."
echo "Create a fine-grained token restricted to ericg2.github.io with Contents: Read and write,"
echo "then run:"
echo "  gh secret set VAULTON_PAGES_TOKEN -R ericg2/Vaulton-UI"
echo
echo "Back up both key files securely. Losing the private key prevents signing"
echo "future repository metadata with the same trusted identity."
