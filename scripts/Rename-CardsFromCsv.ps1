param(
  [string]$CsvPath = ".\card_renames.csv",
  [switch]$Recurse,
  [switch]$WhatIf
)

if (-not (Test-Path -LiteralPath $CsvPath)) { throw "CSV not found: $CsvPath" }

$basePath = (Get-Location).Path
$items = if ($Recurse) { Get-ChildItem -File -Recurse } else { Get-ChildItem -File }

# Build case-insensitive filename lookup
$fileMap = @{}
foreach ($f in $items) { $fileMap[$f.Name.ToLowerInvariant()] = $f.FullName }

$rows = Import-Csv -LiteralPath $CsvPath
if (-not $rows -or $rows.Count -eq 0) { throw "CSV has no rows: $CsvPath" }

# --- Auto-detect columns ---
$props = $rows[0].PSObject.Properties.Name

function Get-ColByPattern($pattern) {
  foreach ($p in $props) {
    $v = ($rows[0].$p ?? "").ToString()
    if ($v -match $pattern) { return $p }
  }
  return $null
}

# Old column likely contains IMG_####
$OldCol = Get-ColByPattern('IMG_\d+\.(jpe?g)$')
if (-not $OldCol) { $OldCol = Get-ColByPattern('IMG_\d+') }

# New column likely contains 2025_... and ends with jpg/jpeg
$NewCol = Get-ColByPattern('^2025_.*\.(jpe?g)$')
if (-not $NewCol) {
  foreach ($p in $props) {
    $v = ($rows[0].$p ?? "").ToString()
    if ($v -match '\.(jpe?g)$' -and $v -notmatch 'IMG_\d+') { $NewCol = $p; break }
  }
}

Write-Host "Detected columns -> Old: '$OldCol'  New: '$NewCol'" -ForegroundColor Cyan
if (-not $OldCol -or -not $NewCol) {
  Write-Host "Could not auto-detect columns. CSV headers are:" -ForegroundColor Yellow
  $props | ForEach-Object { Write-Host " - $_" }
  throw "Fix: specify the correct columns in the script or adjust CSV headers."
}

$renamed = 0
$skippedMissing = 0
$skippedExists  = 0
$skippedBadRow  = 0

foreach ($r in $rows) {
  $oldRaw = ($r.$OldCol ?? "").ToString().Trim()
  $new    = ($r.$NewCol ?? "").ToString().Trim()

  if ([string]::IsNullOrWhiteSpace($oldRaw) -or [string]::IsNullOrWhiteSpace($new)) {
    Write-Host "SKIP (bad row): missing old/new value" -ForegroundColor Yellow
    $skippedBadRow++
    continue
  }

  # If CSV contains a path, reduce to leaf name
  $old = [System.IO.Path]::GetFileName($oldRaw)

  # Normalize jpg/jpeg mismatches
  $oldLower = $old.ToLowerInvariant()
  $tryOlds = @($oldLower)
  if ($oldLower -match '\.jpeg$') { $tryOlds += ($oldLower -replace '\.jpeg$','.jpg') }
  if ($oldLower -match '\.jpg$')  { $tryOlds += ($oldLower -replace '\.jpg$','.jpeg') }

  $srcPath = $null
  foreach ($cand in $tryOlds) {
    if ($fileMap.ContainsKey($cand)) { $srcPath = $fileMap[$cand]; break }
  }

  if (-not $srcPath) {
    Write-Host "SKIP (missing file): $oldRaw" -ForegroundColor DarkYellow
    $skippedMissing++
    continue
  }

  $dstPath = Join-Path (Split-Path $srcPath -Parent) $new
  if (Test-Path -LiteralPath $dstPath) {
    Write-Host "SKIP (target exists): $new" -ForegroundColor DarkYellow
    $skippedExists++
    continue
  }

  if ($WhatIf) {
    Write-Host "WHATIF: $old -> $new" -ForegroundColor Cyan
    continue
  }

  Rename-Item -LiteralPath $srcPath -NewName $new
  Write-Host "Renamed: $old -> $new" -ForegroundColor Green
  $renamed++
}

Write-Host ""
Write-Host "---- SUMMARY ----" -ForegroundColor White
Write-Host "Files in scope:     $($items.Count)"
Write-Host "CSV rows:           $($rows.Count)"
Write-Host "Renamed:            $renamed" -ForegroundColor Green
Write-Host "Skipped (missing):  $skippedMissing" -ForegroundColor Yellow
Write-Host "Skipped (exists):   $skippedExists" -ForegroundColor Yellow
Write-Host "Skipped (bad rows): $skippedBadRow" -ForegroundColor Yellow
