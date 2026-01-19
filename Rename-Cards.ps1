<#
Renames card image files using rename_manifest.csv.

Usage (from repo root):
  pwsh -File .\Rename-Cards.ps1 -SetPath "public\cards\basketball\2025-topps"

What it does:
  - Reads rename_manifest.csv (Original,New)
  - Renames only if the Original file exists in SetPath
  - If the destination name already exists, appends -2, -3, ... before the extension
  - Leaves non-image files alone
#>

param(
  [Parameter(Mandatory=$false)]
  [string]$SetPath = "public\cards\basketball\2025-topps",

  [Parameter(Mandatory=$false)]
  [string]$ManifestPath = "rename_manifest.csv"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $SetPath)) {
  throw "SetPath not found: $SetPath"
}

# Manifest is expected next to this script unless you pass a full path
if (-not (Test-Path -LiteralPath $ManifestPath)) {
  $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
  $candidate = Join-Path $scriptDir $ManifestPath
  if (Test-Path -LiteralPath $candidate) { $ManifestPath = $candidate }
}

if (-not (Test-Path -LiteralPath $ManifestPath)) {
  throw "ManifestPath not found: $ManifestPath"
}

$rows = Import-Csv -LiteralPath $ManifestPath

function Get-UniquePath([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { return $path }
  $dir  = Split-Path -Parent $path
  $name = Split-Path -Leaf $path
  $base = [IO.Path]::GetFileNameWithoutExtension($name)
  $ext  = [IO.Path]::GetExtension($name)
  for ($i=2; $i -lt 1000; $i++) {
    $candidate = Join-Path $dir ("$base-$i$ext")
    if (-not (Test-Path -LiteralPath $candidate)) { return $candidate }
  }
  throw "Too many collisions for: $path"
}

$renamed = 0
$missing = 0
foreach ($r in $rows) {
  $from = Join-Path $SetPath $r.Original
  if (-not (Test-Path -LiteralPath $from)) {
    $missing++
    continue
  }

  $to = Join-Path $SetPath $r.New
  $to = Get-UniquePath $to

  Rename-Item -LiteralPath $from -NewName (Split-Path -Leaf $to)
  $renamed++
}

Write-Host "Done. Renamed: $renamed. Missing originals: $missing." -ForegroundColor Green
