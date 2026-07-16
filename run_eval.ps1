<#
  run_eval.ps1 - build the debug APK, install it on the connected phone, launch
  it, then WAIT. Recite (or tap "Run eval (all clips)" on the Debug Log screen).
  Press Ctrl+C to pull this run's logs + eval files into a timestamped folder.

  Usage:
    .\run_eval.ps1              # build + install + run + (Ctrl+C) pull
    .\run_eval.ps1 -SkipBuild   # skip the APK build (reuse installed app)
    .\run_eval.ps1 -SkipInstall # skip build AND install, just run + pull
#>
param(
  [switch]$SkipBuild,
  [switch]$SkipInstall
)

$ErrorActionPreference = 'Stop'
$pkg = 'com.tilawa.tilawa_ai'
$proj = $PSScriptRoot
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$outDir = Join-Path $proj "pulls\run_$stamp"
$deviceBase = "/sdcard/Android/data/$pkg/files"

# --- device check ---
$devices = (adb devices) | Select-String -Pattern "`tdevice$"
if (-not $devices) {
  Write-Host "No authorized device. Plug in the phone + enable USB debugging." -ForegroundColor Red
  exit 1
}
Write-Host "Device: $($devices[0].ToString().Split("`t")[0])" -ForegroundColor Green

# --- build ---
if (-not $SkipBuild -and -not $SkipInstall) {
  Write-Host "Building debug APK..." -ForegroundColor Cyan
  Push-Location $proj
  flutter build apk --debug
  Pop-Location
}

# --- install ---
$apk = Join-Path $proj "build\app\outputs\flutter-apk\app-debug.apk"
if (-not $SkipInstall) {
  if (-not (Test-Path $apk)) { Write-Host "APK not found: $apk" -ForegroundColor Red; exit 1 }
  Write-Host "Installing $apk ..." -ForegroundColor Cyan
  adb install -r $apk
}

# --- launch ---
Write-Host "Launching $pkg ..." -ForegroundColor Cyan
adb shell monkey -p $pkg -c android.intent.category.LAUNCHER 1 | Out-Null

Write-Host ""
Write-Host "===================================================================" -ForegroundColor Yellow
Write-Host " App is running. On the phone:" -ForegroundColor Yellow
Write-Host "   - Quran tab -> tap the mic and recite (live follow-along), OR" -ForegroundColor Yellow
Write-Host "   - Home -> Debug Log -> 'Run eval (all clips)' for the batch eval." -ForegroundColor Yellow
Write-Host ""
Write-Host " Press Ctrl+C here to PULL this run's logs + eval file." -ForegroundColor Yellow
Write-Host "===================================================================" -ForegroundColor Yellow

try {
  while ($true) { Start-Sleep -Seconds 1 }
}
finally {
  Write-Host ""
  Write-Host "Pulling to $outDir ..." -ForegroundColor Cyan
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null
  # Pull the whole logs + eval dirs (each run's files are already timestamped by
  # the app, so nothing overwrites across runs).
  & adb pull "$deviceBase/logs" $outDir 2>$null
  & adb pull "$deviceBase/eval" $outDir 2>$null
  $pulled = Get-ChildItem -Recurse -File $outDir -ErrorAction SilentlyContinue
  if ($pulled) {
    Write-Host "Pulled $($pulled.Count) file(s):" -ForegroundColor Green
    $pulled | ForEach-Object { Write-Host "   $($_.FullName)" }
    Write-Host ""
    Write-Host "Send me the newest eval_*.json and run_*.log from: $outDir" -ForegroundColor Green
  } else {
    Write-Host "Nothing pulled - did the app write logs yet? (recite / run eval first)" -ForegroundColor Red
  }
}
