<#
  release_build.ps1 - build a RELEASE apk/appbundle that does NOT ship the
  ~16 MB of dev-only test fixtures (assets/debug_audio, assets/eval_audio).

  Flutter bundles every asset declared in pubspec.yaml into every build
  variant -- there's no per-build-mode asset filtering. Those two folders are
  loaded only by the Debug Log screen and the host eval harness, both already
  gated off in release by Log.diagEnabled (kDebugMode / --dart-define=DIAG=true),
  so they're dead weight in a shipped build. This script temporarily removes
  their two lines from pubspec.yaml, builds, then restores the file (even on
  failure) so the normal dev workflow is untouched.

  Usage:
    .\tool\release_build.ps1                 # flutter build appbundle --release
    .\tool\release_build.ps1 -Target apk      # flutter build apk --release
    .\tool\release_build.ps1 -ExtraArgs "--split-per-abi"
#>
param(
  [ValidateSet('appbundle', 'apk')]
  [string]$Target = 'appbundle',
  [string]$ExtraArgs = ''
)

$ErrorActionPreference = 'Stop'
$proj = Split-Path $PSScriptRoot -Parent
$pubspec = Join-Path $proj 'pubspec.yaml'
$backup = "$pubspec.release_build.bak"

Copy-Item $pubspec $backup -Force
try {
  $lines = Get-Content $pubspec | Where-Object {
    $_.Trim() -ne '- assets/debug_audio/' -and $_.Trim() -ne '- assets/eval_audio/'
  }
  Set-Content -Path $pubspec -Value $lines -Encoding utf8

  Write-Host "Building release $Target WITHOUT debug_audio/eval_audio ($((Get-Content $pubspec).Count) pubspec lines, was $((Get-Content $backup).Count))..." -ForegroundColor Cyan
  Push-Location $proj
  try {
    Invoke-Expression "flutter build $Target --release $ExtraArgs"
  } finally {
    Pop-Location
  }
}
finally {
  Copy-Item $backup $pubspec -Force
  Remove-Item $backup -Force
  Write-Host "pubspec.yaml restored." -ForegroundColor DarkGray
}
