#!/usr/bin/env bash
set -Eeuo pipefail

# Publish a Vaulton release from the repository root.
# The release workflows in .github/workflows build and attach every package
# (Android, Windows and Linux). Authentication is provided by the GitHub CLI
# (gh auth login); no tokens or signing credentials belong in this script or in
# source control.

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

NOTES_FILE=""
NOTES=""
YES=0

usage() {
  cat <<'EOF'
Usage: ./tool/publish-release.sh [options]

Options:
  --notes TEXT       Use custom release notes (otherwise GitHub generates them).
  --notes-file FILE  Read custom release notes from a Markdown file.
  --yes              Skip the final confirmation prompt.
  -h, --help         Show this help.

Requirements:
  git, Flutter, GitHub CLI (gh), and an authenticated gh session.

The Android signing key lives in repository secrets, so no signing file is
needed on this machine.
EOF
}

while (($#)); do
  case "$1" in
    --notes)
      [[ $# -ge 2 ]] || { echo "Missing value for --notes." >&2; exit 2; }
      NOTES="$2"; shift 2 ;;
    --notes-file)
      [[ $# -ge 2 ]] || { echo "Missing value for --notes-file." >&2; exit 2; }
      NOTES_FILE="$2"; shift 2 ;;
    --yes) YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -n "$NOTES" && -n "$NOTES_FILE" ]]; then
  echo "Use either --notes or --notes-file, not both." >&2
  exit 2
fi

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command '$1' was not found." >&2
    exit 1
  }
}
for command in git flutter gh; do require_command "$command"; done

[[ "$(git branch --show-current)" == "main" ]] || {
  echo "Switch to main before publishing." >&2
  exit 1
}
[[ -z "$(git status --porcelain)" ]] || {
  echo "The working tree must be clean. Commit or stash changes before publishing." >&2
  exit 1
}
git remote get-url origin >/dev/null
gh auth status >/dev/null

PUBSPEC="pubspec.yaml"
SETTINGS="lib/features/settings/settings_page.dart"
VERSION_LINE="$(grep -E '^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+[[:space:]]*$' "$PUBSPEC" || true)"
[[ -n "$VERSION_LINE" ]] || { echo "Could not read X.Y.Z+build from pubspec.yaml." >&2; exit 1; }
CURRENT="${VERSION_LINE#version:}"
CURRENT="${CURRENT//[[:space:]]/}"
IFS='+.' read -r MAJOR MINOR PATCH BUILD <<< "$CURRENT"
NEXT_PATCH=$((PATCH + 1))
NEXT_BUILD=$((BUILD + 1))
VERSION="$MAJOR.$MINOR.$NEXT_PATCH"
TAG="v$VERSION"

grep -q "const kAppVersion = '[^']*';" "$SETTINGS" || {
  echo "Could not find kAppVersion in $SETTINGS." >&2
  exit 1
}
if git tag --list "$TAG" | grep -q . || git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
  echo "Release tag $TAG already exists locally or remotely." >&2
  exit 1
fi

if [[ -n "$NOTES_FILE" ]]; then
  [[ -f "$NOTES_FILE" ]] || { echo "Notes file not found: $NOTES_FILE" >&2; exit 1; }
  NOTES="$(cat "$NOTES_FILE")"
fi

printf '\nVaulton release preview\n  Version: %s (build %s)\n  Tag:     %s\n' "$VERSION" "$NEXT_BUILD" "$TAG"
if [[ "$YES" -ne 1 ]]; then
  read -r -p "Commit, push main, and publish this release? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }
fi

PUBSPEC_BACKUP="$(mktemp)"
SETTINGS_BACKUP="$(mktemp)"
cp "$PUBSPEC" "$PUBSPEC_BACKUP"
cp "$SETTINGS" "$SETTINGS_BACKUP"
COMMITTED=0
cleanup() {
  if [[ "$COMMITTED" -eq 0 ]]; then
    cp "$PUBSPEC_BACKUP" "$PUBSPEC"
    cp "$SETTINGS_BACKUP" "$SETTINGS"
    git checkout -- pubspec.lock 2>/dev/null || true
  fi
  rm -f "$PUBSPEC_BACKUP" "$SETTINGS_BACKUP"
}
trap cleanup EXIT

sed -i -E "s/^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+[[:space:]]*$/version: $VERSION+$NEXT_BUILD/" "$PUBSPEC"
sed -i -E "s/const kAppVersion = '[^']*';/const kAppVersion = '$VERSION';/" "$SETTINGS"

echo "Resolving Flutter dependencies..."
flutter pub get

git add -- "$PUBSPEC" pubspec.lock "$SETTINGS"
git commit -m "Prepare Vaulton UI release $TAG"
COMMITTED=1
git push origin main

RELEASE_ARGS=(release create "$TAG" --title "Vaulton $VERSION" --target main)
if [[ -n "$NOTES" ]]; then
  RELEASE_ARGS+=(--notes "$NOTES")
else
  RELEASE_ARGS+=(--generate-notes)
fi

gh "${RELEASE_ARGS[@]}"

printf '\nPublished Vaulton %s successfully.\n' "$VERSION"
printf 'Release: https://github.com/ericg2/Vaulton-UI/releases/tag/%s\n' "$TAG"
printf 'The Android, Windows and Linux packages are built by the release workflows.\n'
printf 'Watch them in the Actions tab: https://github.com/ericg2/Vaulton-UI/actions\n'
