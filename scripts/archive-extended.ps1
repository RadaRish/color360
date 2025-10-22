$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
$dest = Join-Path $root "archive/2025-10-22-extended"
if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest | Out-Null }

$patterns = @(
  'emergency-*.sh',
  'super-emergency-*.sh',
  'nuclear-*.sh',
  'diagnose-*.sh',
  'diagnostic-*.sh'
)

$archived = @()
foreach ($pat in $patterns) {
  Get-ChildItem -Path $root -Filter $pat -File -Recurse:$false | ForEach-Object {
    $src = $_.FullName
    $tgt = Join-Path $dest $_.Name
    Move-Item -LiteralPath $src -Destination $tgt -Force
    $archived += @{ src = $src; dst = $tgt }
    Write-Output ("Archived: {0} -> {1}" -f $src, $tgt)
  }
}

$log = Join-Path $dest "CLEANUP-ARCHIVE-2025-10-22-EXTENDED.log"
"# Extended Archive log $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File -Encoding UTF8 -FilePath $log
foreach ($item in $archived) { "{0} -> {1}" -f $item.src, $item.dst | Add-Content -Encoding UTF8 $log }
"Total archived: $($archived.Count)" | Add-Content -Encoding UTF8 $log
Write-Output ("Total archived: {0}" -f $archived.Count)
