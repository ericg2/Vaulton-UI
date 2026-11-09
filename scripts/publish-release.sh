#!/usr/bin/env bash
set -Eeuo pipefail

# Publish an Android Vaulton release from the repository root.
# Authentication is provided by the GitHub CLI (gh auth login); no tokens or
# signing credentials belong in this script or in source control.

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
  git, Flutter, GitHub CLI (gh), an authenticated gh session, and a configured
  Android release signing file at android/key.properties.

The signing file and keystore must remain private and must never be committed.
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

[[ -f android/key.properties ]] || {
  echo "Android signing is not configured. Run ./tool/setup-signing.sh first; see tool/README.md for key locations and backup instructions." >&2
  exit 1
}
git check-ignore -q android/key.properties || {
  echo "android/key.properties is not ignored by Git. Refusing to continue to protect signing credentials." >&2
  exit 1
}
git ls-files --error-unmatch android/key.properties >/dev/null 2>&1 && {
  echo "android/key.properties is tracked by Git. Remove it from source control and rotate the signing credentials before publishing." >&2
  exit 1
}
[[ "$(git branch --show-current)" == "main" ]] || {
  echo "Switch to main before publishing." >&2
  exit 1
}
[[ -z "$(git status --porcelain)" ]] || {
  echo "The working tree must be clean. Commit or stash changes before publishing." >&2
  exit 1
}


# Releases must be built from the current main branch so Android SDK and
# Gradle requirements cannot silently come from an older local checkout.
git fetch origin main --tags
LOCAL_HEAD="$(git rev-parse HEAD)"
REMOTE_HEAD="$(git rev-parse origin/main)"
[[ "$LOCAL_HEAD" == "$REMOTE_HEAD" ]] || {
  echo "Local main is not up to date with origin/main." >&2
  echo "Run: git pull --ff-only origin main" >&2
  exit 1
}
grep -Eq '^[[:space:]]*compileSdk[[:space:]]*=[[:space:]]*37[[:space:]]*git remote get-url origin >/dev/null
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

printf '\nVaulton release preview\n  Version: %s (build %s)\n  Tag:     %s\n  Target:  Android APK\n' "$VERSION" "$NEXT_BUILD" "$TAG"
if [[ "$YES" -ne 1 ]]; then
  read -r -p "Build, commit, push main, and publish this release? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }
fi

PUBSPEC_BACKUP="$(mktemp)"
SETTINGS_BACKUP="$(mktemp)"
cp "$PUBSPEC" "$PUBSPEC_BACKUP"
cp "$SETTINGS" "$SETTINGS_BACKUP"
STAGE="$(mktemp -d)"
COMMITTED=0
cleanup() {
  if [[ "$COMMITTED" -eq 0 ]]; then
    cp "$PUBSPEC_BACKUP" "$PUBSPEC"
    cp "$SETTINGS_BACKUP" "$SETTINGS"
    git checkout -- pubspec.lock 2>/dev/null || true
  fi
  rm -f "$PUBSPEC_BACKUP" "$SETTINGS_BACKUP"
  rm -rf "$STAGE"
}
trap cleanup EXIT

sed -i -E "s/^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+[[:space:]]*$/version: $VERSION+$NEXT_BUILD/" "$PUBSPEC"
sed -i -E "s/const kAppVersion = '[^']*';/const kAppVersion = '$VERSION';/" "$SETTINGS"

echo "Resolving Flutter dependencies..."
flutter pub get

echo "Building signed Android release..."
flutter build apk --release
APK="build/app/outputs/flutter-apk/app-release.apk"
[[ -s "$APK" ]] || { echo "APK build output not found: $APK" >&2; exit 1; }

cp "$APK" "$STAGE/Vaulton-Android.apk"
(
  cd "$STAGE"
  sha256sum Vaulton-Android.apk > Vaulton-Android.apk.sha256
)

git add -- "$PUBSPEC" pubspec.lock "$SETTINGS"
git commit -m "Prepare Vaulton UI release $TAG"
COMMITTED=1
git push origin main

RELEASE_ARGS=(release create "$TAG" "$STAGE/Vaulton-Android.apk" "$STAGE/Vaulton-Android.apk.sha256" --title "Vaulton $VERSION" --target main)
if [[ -n "$NOTES" ]]; then
  RELEASE_ARGS+=(--notes "$NOTES")
else
  RELEASE_ARGS+=(--generate-notes)
fi

gh "${RELEASE_ARGS[@]}"

printf '\nPublished Vaulton %s successfully.\n' "$VERSION"
printf 'Release: https://github.com/ericg2/Vaulton-UI/releases/tag/%s\n' "$TAG"
printf 'Windows and Linux assets are not built by this Android-only script.\n'
 android/app/build.gradle.kts || {
  echo "Android release configuration must compile against SDK 37. Update main before publishing." >&2
  exit 1
}
grep -Eq 'id\("com\.android\.application"\)[[:space:]]+version[[:space:]]+"9\.1\.1"[[:space:]]+apply false' android/settings.gradle.kts || {
  echo "Android Gradle Plugin 9.1.1 is required for compileSdk 37. Update main before publishing." >&2
  exit 1
}
grep -q '^android.builtInKotlin=truegit remote get-url origin >/dev/null
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

printf '\nVaulton release preview\n  Version: %s (build %s)\n  Tag:     %s\n  Target:  Android APK\n' "$VERSION" "$NEXT_BUILD" "$TAG"
if [[ "$YES" -ne 1 ]]; then
  read -r -p "Build, commit, push main, and publish this release? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }
fi

PUBSPEC_BACKUP="$(mktemp)"
SETTINGS_BACKUP="$(mktemp)"
cp "$PUBSPEC" "$PUBSPEC_BACKUP"
cp "$SETTINGS" "$SETTINGS_BACKUP"
STAGE="$(mktemp -d)"
COMMITTED=0
cleanup() {
  if [[ "$COMMITTED" -eq 0 ]]; then
    cp "$PUBSPEC_BACKUP" "$PUBSPEC"
    cp "$SETTINGS_BACKUP" "$SETTINGS"
    git checkout -- pubspec.lock 2>/dev/null || true
  fi
  rm -f "$PUBSPEC_BACKUP" "$SETTINGS_BACKUP"
  rm -rf "$STAGE"
}
trap cleanup EXIT

sed -i -E "s/^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+[[:space:]]*$/version: $VERSION+$NEXT_BUILD/" "$PUBSPEC"
sed -i -E "s/const kAppVersion = '[^']*';/const kAppVersion = '$VERSION';/" "$SETTINGS"

echo "Resolving Flutter dependencies..."
flutter pub get

echo "Building signed Android release..."
flutter build apk --release
APK="build/app/outputs/flutter-apk/app-release.apk"
[[ -s "$APK" ]] || { echo "APK build output not found: $APK" >&2; exit 1; }

cp "$APK" "$STAGE/Vaulton-Android.apk"
(
  cd "$STAGE"
  sha256sum Vaulton-Android.apk > Vaulton-Android.apk.sha256
)

git add -- "$PUBSPEC" pubspec.lock "$SETTINGS"
git commit -m "Prepare Vaulton UI release $TAG"
COMMITTED=1
git push origin main

RELEASE_ARGS=(release create "$TAG" "$STAGE/Vaulton-Android.apk" "$STAGE/Vaulton-Android.apk.sha256" --title "Vaulton $VERSION" --target main)
if [[ -n "$NOTES" ]]; then
  RELEASE_ARGS+=(--notes "$NOTES")
else
  RELEASE_ARGS+=(--generate-notes)
fi

gh "${RELEASE_ARGS[@]}"

printf '\nPublished Vaulton %s successfully.\n' "$VERSION"
printf 'Release: https://github.com/ericg2/Vaulton-UI/releases/tag/%s\n' "$TAG"
printf 'Windows and Linux assets are not built by this Android-only script.\n'
 android/gradle.properties || {
  echo "Android built-in Kotlin migration is missing. Update main before publishing." >&2
  exit 1
}
[[ -z "$(git status --porcelain)" ]] || {
  echo "The working tree must be clean after fetching. Commit or stash changes before publishing." >&2
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

printf '\nVaulton release preview\n  Version: %s (build %s)\n  Tag:     %s\n  Target:  Android APK\n' "$VERSION" "$NEXT_BUILD" "$TAG"
if [[ "$YES" -ne 1 ]]; then
  read -r -p "Build, commit, push main, and publish this release? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }
fi

PUBSPEC_BACKUP="$(mktemp)"
SETTINGS_BACKUP="$(mktemp)"
cp "$PUBSPEC" "$PUBSPEC_BACKUP"
cp "$SETTINGS" "$SETTINGS_BACKUP"
STAGE="$(mktemp -d)"
COMMITTED=0
cleanup() {
  if [[ "$COMMITTED" -eq 0 ]]; then
    cp "$PUBSPEC_BACKUP" "$PUBSPEC"
    cp "$SETTINGS_BACKUP" "$SETTINGS"
    git checkout -- pubspec.lock 2>/dev/null || true
  fi
  rm -f "$PUBSPEC_BACKUP" "$SETTINGS_BACKUP"
  rm -rf "$STAGE"
}
trap cleanup EXIT

sed -i -E "s/^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+[[:space:]]*$/version: $VERSION+$NEXT_BUILD/" "$PUBSPEC"
sed -i -E "s/const kAppVersion = '[^']*';/const kAppVersion = '$VERSION';/" "$SETTINGS"

echo "Resolving Flutter dependencies..."
flutter pub get

echo "Building signed Android release..."
flutter build apk --release
APK="build/app/outputs/flutter-apk/app-release.apk"
[[ -s "$APK" ]] || { echo "APK build output not found: $APK" >&2; exit 1; }

cp "$APK" "$STAGE/Vaulton-Android.apk"
(
  cd "$STAGE"
  sha256sum Vaulton-Android.apk > Vaulton-Android.apk.sha256
)

git add -- "$PUBSPEC" pubspec.lock "$SETTINGS"
git commit -m "Prepare Vaulton UI release $TAG"
COMMITTED=1
git push origin main

RELEASE_ARGS=(release create "$TAG" "$STAGE/Vaulton-Android.apk" "$STAGE/Vaulton-Android.apk.sha256" --title "Vaulton $VERSION" --target main)
if [[ -n "$NOTES" ]]; then
  RELEASE_ARGS+=(--notes "$NOTES")
else
  RELEASE_ARGS+=(--generate-notes)
fi

gh "${RELEASE_ARGS[@]}"

printf '\nPublished Vaulton %s successfully.\n' "$VERSION"
printf 'Release: https://github.com/ericg2/Vaulton-UI/releases/tag/%s\n' "$TAG"
printf 'Windows and Linux assets are not built by this Android-only script.\n'
