param(
  [ValidateSet("Archive","Delete")]
  [string]$Mode = "Archive"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = Resolve-Path (Join-Path $root "..")
Set-Location $repo

$timestamp = Get-Date -Format "yyyy-MM-dd"
$archiveDir = Join-Path $repo "archive/$timestamp"

$targets = @(
  "pano/backup/scene_list.js",
  "pano/backup/retouch_manager.js",
  "pano/backup/hotspot-editor.js",
  "patch-full-retouch-changes.diff",
  "patch-retouch_manager.diff",
  "test-syntax.sh",
  "test-lama-access.sh",
  "scripts/smoke-test-retouch.sh"
)

Write-Host "Cleanup mode:" $Mode

if ($Mode -eq "Archive") {
  if (-not (Test-Path $archiveDir)) {
    New-Item -ItemType Directory -Force -Path $archiveDir | Out-Null
  }
}

foreach ($rel in $targets) {
  $path = Join-Path $repo $rel
  if (Test-Path $path) {
    if ($Mode -eq "Archive") {
      $dest = Join-Path $archiveDir $rel
      $destDir = Split-Path -Parent $dest
      if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Force -Path $destDir | Out-Null }
      Write-Host "Archiving" $rel "->" $dest
      Move-Item -Force -Path $path -Destination $dest
    } elseif ($Mode -eq "Delete") {
      Write-Host "Deleting" $rel
      Remove-Item -Force -Path $path
    }
  } else {
    Write-Host "Skip (not found):" $rel
  }
}

Write-Host "Done." -ForegroundColor Green
