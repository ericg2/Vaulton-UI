<#
.SYNOPSIS
  One-time setup of a permanent Android signing key for Vaulton.

.DESCRIPTION
  Android only installs an update over an existing app when both APKs are signed with the
  SAME key. Without android/key.properties the release build falls back to this PC's debug
  key, which changes if the Android SDK folder is recreated or you build on another PC, and
  then installs fail with "App not installed".

  This script creates android/key.properties pointing at a keystore stored OUTSIDE the repo
  (%USERPROFILE%\.vaulton\vaulton-release.jks), so it can't be committed by accident.

  Default: reuses your existing debug keystore (%USERPROFILE%\.android\debug.keystore) so any
  install that was built on this PC keeps updating. If none exists, a new key is generated.
  -NewKey: always generate a brand new key. Phones with an app signed by an older key must
  uninstall it once before installing a build signed with the new key.

  BACK UP %USERPROFILE%\.vaulton\ somewhere safe. If you lose it, you can never update
  installed copies again.
#>
param(
    [switch]$NewKey
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$propsPath = Join-Path $root 'android/key.properties'
$keyDir = Join-Path $env:USERPROFILE '.vaulton'
$store = Join-Path $keyDir 'vaulton-release.jks'
$debugStore = Join-Path $env:USERPROFILE '.android/debug.keystore'

if (Test-Path $propsPath) {
    Write-Host "android/key.properties already exists. Delete it first if you really want to replace it." -ForegroundColor Yellow
    exit 0
}

New-Item -ItemType Directory -Path $keyDir -Force | Out-Null

if (-not $NewKey -and (Test-Path $debugStore)) {
    Write-Host 'Reusing this PC''s existing debug key as the permanent release key...' -ForegroundColor Cyan
    Copy-Item $debugStore $store -Force
    $alias = 'androiddebugkey'
    $storePass = 'android'
    $keyPass = 'android'
} else {
    if (Test-Path $store) { throw "A keystore already exists at $store. Move it away or reuse it." }
    if (-not (Get-Command keytool -ErrorAction SilentlyContinue)) {
        throw "keytool was not found. It ships with the JDK / Android Studio (jbr\bin). Add it to PATH and retry."
    }
    Write-Host 'Generating a new signing key...' -ForegroundColor Cyan
    $alias = 'vaulton'
    $bytes = New-Object byte[] 24
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $storePass = ([Convert]::ToBase64String($bytes)) -replace '[^A-Za-z0-9]', 'x'
    $keyPass = $storePass
    keytool -genkeypair -v -keystore $store -storetype JKS -alias $alias -keyalg RSA -keysize 2048 `
        -validity 36500 -storepass $storePass -keypass $keyPass -dname 'CN=Vaulton, O=Vaulton, C=US'
    if ($LASTEXITCODE -ne 0) { throw 'keytool failed to create the keystore.' }
}

$storeFile = $store -replace '\\', '/'
$lines = @(
    "storePassword=$storePass",
    "keyPassword=$keyPass",
    "keyAlias=$alias",
    "storeFile=$storeFile"
)
[System.IO.File]::WriteAllLines($propsPath, $lines, [System.Text.UTF8Encoding]::new($false))

Write-Host ''
Write-Host 'Signing key ready.' -ForegroundColor Green
Write-Host "  Keystore:   $store"
Write-Host "  Properties: $propsPath (git-ignored)"
Write-Host ''
Write-Host 'IMPORTANT: back up the .vaulton folder (keystore + the passwords in key.properties).' -ForegroundColor Yellow
Write-Host 'If an install still fails, uninstall the old Vaulton from the phone once, then install the new APK.'
