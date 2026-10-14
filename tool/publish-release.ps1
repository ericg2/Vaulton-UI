param(
    [string]$ReleaseNotes
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Require-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found. Install it and retry."
    }
}

Require-Command 'git'
Require-Command 'flutter'
Require-Command 'gh'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $root
try {
    if (-not (Test-Path (Join-Path $root 'android/key.properties'))) {
        throw 'No android/key.properties. Releases would be signed with a throwaway debug key and fail to update over installed apps. Run .\tool\setup-signing.ps1 first.'
    }
    $branch = (git branch --show-current).Trim()
    if ($branch -ne 'main') {
        throw "Switch to the main branch before publishing (current branch: '$branch')."
    }
    $workingTree = (git status --porcelain | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not inspect the Git working tree.'
    }
    if ($workingTree) {
        throw 'The working tree is not clean. Commit or stash your changes before publishing.'
    }
    gh auth status | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'GitHub CLI is not authenticated. Run: gh auth login'
    }

    $pubspecPath = Join-Path $root 'pubspec.yaml'
    $settingsPath = Join-Path $root 'lib/features/settings/settings_page.dart'
    $pubspec = Get-Content $pubspecPath -Raw
    $settings = Get-Content $settingsPath -Raw

    $versionMatch = [regex]::Match($pubspec, '(?m)^version:[ \t]*(\d+)\.(\d+)\.(\d+)\+(\d+)[ \t]*$')
    if (-not $versionMatch.Success) {
        throw 'Could not parse version from pubspec.yaml (expected X.Y.Z+build).'
    }

    $major = [int]$versionMatch.Groups[1].Value
    $minor = [int]$versionMatch.Groups[2].Value
    $patch = [int]$versionMatch.Groups[3].Value + 1
    $build = [int]$versionMatch.Groups[4].Value + 1
    $version = "$major.$minor.$patch"
    $tag = "v$version"

    $localTag = (git tag --list $tag | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not inspect local Git tags.'
    }
    if ($localTag) {
        throw "Tag $tag already exists locally. Update the version before publishing."
    }
    $remoteTag = git ls-remote --tags origin "refs/tags/$tag"
    if ($remoteTag) {
        throw "Tag $tag already exists on GitHub. Update the version before publishing."
    }

    if ($settings -notmatch "const kAppVersion = '[^']+';") {
        throw 'Could not find kAppVersion in the Settings page.'
    }
    $newPubspec = [regex]::Replace($pubspec, '(?m)^version:[ \t]*\d+\.\d+\.\d+\+\d+[ \t]*$', "version: $version+$build")
    $newSettings = [regex]::Replace($settings, "const kAppVersion = '[^']+';", "const kAppVersion = '$version';")
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($pubspecPath, $newPubspec, $utf8NoBom)
    [System.IO.File]::WriteAllText($settingsPath, $newSettings, $utf8NoBom)

    try {
        Write-Host "Preparing Vaulton v$version (build $build)..." -ForegroundColor Cyan
        flutter pub get
        if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }

        Write-Host 'Building Android APK...' -ForegroundColor Cyan
        flutter build apk --release
        if ($LASTEXITCODE -ne 0) { throw 'Flutter Android release build failed.' }

        $builtApk = Join-Path $root 'build/app/outputs/flutter-apk/app-release.apk'
        if (-not (Test-Path $builtApk)) { throw "Android build output not found: $builtApk" }

        $stage = Join-Path ([System.IO.Path]::GetTempPath()) "vaulton-release-$version"
        if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
        New-Item -ItemType Directory -Path $stage | Out-Null
        $apk = Join-Path $stage 'Vaulton-Android.apk'
        Copy-Item $builtApk $apk
        $androidHash = (Get-FileHash $apk -Algorithm SHA256).Hash.ToLowerInvariant()
        $androidChecksum = Join-Path $stage 'Vaulton-Android.apk.sha256'
        Set-Content -Path $androidChecksum -Value "$androidHash  Vaulton-Android.apk" -Encoding ascii

        git add -- pubspec.yaml pubspec.lock lib/features/settings/settings_page.dart
        git commit -m "Prepare Vaulton UI release $tag"
        if ($LASTEXITCODE -ne 0) { throw 'Could not commit the release version.' }
        git push origin main
        if ($LASTEXITCODE -ne 0) { throw 'Could not push the release version to origin/main.' }

        if ([string]::IsNullOrWhiteSpace($ReleaseNotes)) {
            gh release create $tag $apk $androidChecksum --title "Vaulton $version" --generate-notes --target main
        } else {
            gh release create $tag $apk $androidChecksum --title "Vaulton $version" --notes $ReleaseNotes --target main
        }
        if ($LASTEXITCODE -ne 0) { throw 'The APK was built and the version commit was pushed, but creating the GitHub Release failed. Re-run after resolving the GitHub CLI error.' }

        Write-Host ""
        Write-Host "Published Vaulton v$version successfully." -ForegroundColor Green
        Write-Host "Android assets are available now; Windows and Linux installers are built by GitHub Actions." -ForegroundColor Cyan
        Write-Host "Release: https://github.com/ericg2/Vaulton-UI/releases/tag/$tag"
    }
    catch {
        $workingTreeAfterFailure = (git status --porcelain | Out-String).Trim()
        if ($workingTreeAfterFailure) {
            Write-Warning 'The release did not finish cleanly. Check git status before retrying; do not run the script again until you have reviewed any changes.'
        }
        throw
    }
}
finally {
    Pop-Location
}
