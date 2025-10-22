$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
$docs = Join-Path $root 'docs'
$legacy = Join-Path $docs 'legacy'
if (-not (Test-Path $docs)) { New-Item -ItemType Directory -Path $docs | Out-Null }
if (-not (Test-Path $legacy)) { New-Item -ItemType Directory -Path $legacy | Out-Null }

function Move-IfExists($from, $toDir) {
  if (Test-Path $from) {
    $file = Split-Path -Leaf $from
    $dest = Join-Path $toDir $file
    Move-Item -LiteralPath $from -Destination $dest -Force
    Write-Output ("Moved: {0} -> {1}" -f $from, $dest)
  }
}

# Root docs to docs/
$toDocs = @(
  'DEPLOYMENT.md',
  'DEPLOYMENT-PRODUCTION.md',
  'PRODUCTION-INSTALL-GUIDE.md',
  'LAMA-SETUP.md',
  'AI-SETUP-GUIDE.md',
  'ARROW_ICON_CHANGES.md',
  'TRIAL-VERSION-GUIDE.md'
)
foreach ($f in $toDocs) { Move-IfExists (Join-Path $root $f) $docs }

# Root docs to legacy/
$toLegacy = @(
  'INSTALL-RU.md',
  'INSTALL-REG-RU.md',
  'INSTALL-UPDATE-GUIDE.md',
  'LAMA-SETUP-GUIDE.md',
  'FAQ-UPDATE.md'
)
foreach ($f in $toLegacy) { Move-IfExists (Join-Path $root $f) $legacy }

# From pano/
$fromPanoToDocs = @(
  'INSTALL.md',
  'DEPLOY.md',
  'ARCHITECTURE_PLAN.md'
)
foreach ($f in $fromPanoToDocs) { Move-IfExists (Join-Path $root ('pano/' + $f)) $docs }

Write-Output 'DONE'
