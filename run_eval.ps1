<#
  run_eval.ps1 - build a FRESH debug APK (latest code, incl. the Hadith tab),
  install it on the connected phone, launch it, then WAIT while you test on the
  device. The app captures a full atom-level trace to its on-device file sink
  (Log.initFileSink -> /sdcard/Android/data/<pkg>/files/logs/run_*.log). Press
  [S] to SAVE + PULL this run's logs + eval files into a timestamped folder.
  (Ctrl+C is a backup; the [S] keypress is the reliable stop.)

  Debug builds enable the file sink (Log.diagEnabled = kDebugMode); a release
  build would write nothing, so ALWAYS test with this debug APK.

  Test the Hadith voice-search: open the Hadith tab, tap the mic, recite a
  hadith; the log's [hadithfind] lines trace every probe (heard phonemes, top
  candidates + scores, floor/margin/streak, and WHY each pick fired or didn't).

  Usage:
    .\run_eval.ps1              # build + install + run + (Ctrl+C) save & pull
    .\run_eval.ps1 -SkipBuild   # skip the APK build (reuse installed app)
    .\run_eval.ps1 -SkipInstall # skip build AND install, just run + pull
#>
param(
  [switch]$SkipBuild,
  [switch]$SkipInstall
)

$ErrorActionPreference = 'Stop'
$pkg = 'com.sanad.sanad'
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

# Pull is a function so the primary (keypress) path and the Ctrl+C backup call
# the same code. A guard makes it run at most once per invocation.
$script:pullDone = $false
function Invoke-SavePull {
  if ($script:pullDone) { return }
  $script:pullDone = $true
  Write-Host ""
  Write-Host "Pulling to $outDir ..." -ForegroundColor Cyan
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null
  # Pull the whole logs + eval (+ recordings, if the app ever writes any) dirs.
  # Each run's files are already timestamped by the app, so nothing overwrites
  # across runs. adb pull is silent (2>$null) when a dir doesn't exist.
  & adb pull "$deviceBase/logs" $outDir 2>$null
  & adb pull "$deviceBase/eval" $outDir 2>$null
  & adb pull "$deviceBase/recordings" $outDir 2>$null
  $pulled = Get-ChildItem -Recurse -File $outDir -ErrorAction SilentlyContinue
  if ($pulled) {
    Write-Host "Pulled $($pulled.Count) file(s):" -ForegroundColor Green
    $pulled | ForEach-Object { Write-Host "   $($_.FullName)" }
    Write-Host ""
    Write-Host "Send me the newest run_*.log (grep [hadithfind] for the search trace)" -ForegroundColor Green
    Write-Host "and any eval_*.json from: $outDir" -ForegroundColor Green
  } else {
    Write-Host "Nothing pulled - did the app write logs yet? (recite / run eval first)" -ForegroundColor Red
  }
}

Write-Host ""
Write-Host "===================================================================" -ForegroundColor Yellow
Write-Host " App is running. On the phone:" -ForegroundColor Yellow
Write-Host "   - Hadith tab -> tap the mic and recite a hadith (voice-search), OR" -ForegroundColor Yellow
Write-Host "   - Quran tab  -> tap the mic and recite (live follow-along), OR" -ForegroundColor Yellow
Write-Host "   - Home -> Debug Log -> 'Run eval (all clips)' for the batch eval." -ForegroundColor Yellow
Write-Host ""
Write-Host " Recite your tests, then press [S] to stop and pull logs." -ForegroundColor Yellow
Write-Host "===================================================================" -ForegroundColor Yellow

# Primary stop: poll the keyboard for 's'. Assumes an INTERACTIVE console (the
# only way this script is used) — [Console]::KeyAvailable throws under a
# redirected/non-interactive stdin, which the catch below turns into the Ctrl+C
# backup path. The 200ms sleep keeps the poll from busy-spinning.
try {
  while ($true) {
    if ([Console]::KeyAvailable) {
      $key = [Console]::ReadKey($true)
      if ($key.Key -eq 'S') { break }
    }
    Start-Sleep -Milliseconds 200
  }
  Invoke-SavePull
}
finally {
  # Backup only: if a real Ctrl+C (or a KeyAvailable failure) unwinds us before
  # the keypress break, still attempt the pull. The guard skips a second run.
  Invoke-SavePull
}
