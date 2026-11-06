#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PROPS="$ROOT/android/key.properties"
KEY_DIR="${HOME}/.vaulton"
KEYSTORE="$KEY_DIR/vaulton-release.jks"
DEBUG_KEY="${HOME}/.android/debug.keystore"
NEW_KEY=0

usage() {
  cat <<'EOF'
Set up Vaulton's permanent Android release signing key.

Usage: ./tool/setup-signing.sh [--new-key]

Default behavior reuses ~/.android/debug.keystore when present to preserve
existing debug-signed installs. If no debug key exists, a dedicated key is made.

Options:
  --new-key  Generate a dedicated key even if a debug key exists.
  -h, --help Show this help.

Private keystore: ~/.vaulton/vaulton-release.jks
Gradle settings:  android/key.properties
EOF
}

while (($#)); do
  case "$1" in
    --new-key) NEW_KEY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -f "$PROPS" ]]; then
  echo "Signing is already configured in android/key.properties."
  echo "Configured keystore:"
  sed -n 's/^storeFile=//p' "$PROPS" | head -n 1
  echo "Back up the keystore and android/key.properties securely."
  exit 0
fi

git -C "$ROOT" check-ignore -q android/key.properties || {
  echo "android/key.properties is not Git-ignored. Refusing to write credentials." >&2
  exit 1
}

mkdir -p "$KEY_DIR"
chmod 700 "$KEY_DIR"

if [[ "$NEW_KEY" -eq 0 && -f "$DEBUG_KEY" ]]; then
  echo "Reusing the existing Android debug key to preserve existing install signatures."
  echo "Warning: the Android debug key has a publicly known password."
  echo "Use --new-key for a dedicated production signing key."
  install -m 600 "$DEBUG_KEY" "$KEYSTORE"
  ALIAS="androiddebugkey"
  STORE_PASS="android"
  KEY_PASS="android"
else
  command -v keytool >/dev/null 2>&1 || {
    echo "keytool not found. Install a JDK or add Android Studio's JBR bin directory to PATH." >&2
    exit 1
  }
  command -v openssl >/dev/null 2>&1 || {
    echo "openssl is required to generate a strong keystore password." >&2
    exit 1
  }
  [[ ! -e "$KEYSTORE" ]] || {
    echo "A keystore already exists at $KEYSTORE. Refusing to overwrite it." >&2
    echo "Restore its matching android/key.properties or move it aside intentionally." >&2
    exit 1
  }
  ALIAS="vaulton"
  STORE_PASS="$(openssl rand -hex 32)"
  KEY_PASS="$STORE_PASS"
  echo "Generating a dedicated Vaulton Android signing key..."
  keytool -genkeypair -v -keystore "$KEYSTORE" -storetype JKS -alias "$ALIAS" \
    -keyalg RSA -keysize 2048 -validity 36500 \
    -storepass "$STORE_PASS" -keypass "$KEY_PASS" \
    -dname 'CN=Vaulton, O=Vaulton, C=US'
  chmod 600 "$KEYSTORE"
fi

[[ -s "$KEYSTORE" ]] || { echo "Keystore creation failed." >&2; exit 1; }
PROPS_TMP="$(mktemp "$ROOT/android/.key.properties.XXXXXX")"
trap 'rm -f "$PROPS_TMP"' EXIT
{
  printf 'storePassword=%s\n' "$STORE_PASS"
  printf 'keyPassword=%s\n' "$KEY_PASS"
  printf 'keyAlias=%s\n' "$ALIAS"
  printf 'storeFile=%s\n' "$KEYSTORE"
} > "$PROPS_TMP"
chmod 600 "$PROPS_TMP"
mv "$PROPS_TMP" "$PROPS"
trap - EXIT

echo
echo "Android signing is configured."
echo "  Keystore:   $KEYSTORE"
echo "  Properties: $PROPS (Git-ignored)"
echo
echo "Back up BOTH files securely. Losing the key or its passwords prevents"
echo "updates to existing installations signed with this key. Never commit them."
