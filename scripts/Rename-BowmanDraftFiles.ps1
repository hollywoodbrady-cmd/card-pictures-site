<#
Renames Bowman Draft 2025 assets in:
  public\cards\baseball\bowman-2025-pro-debut\front-webp
  public\cards\baseball\bowman-2025-pro-debut\back-webp
  public\cards\baseball\bowman-2025-pro-debut\thumbs

Adds:
  - __bd-### where mapped
  - __1st-bowman__ for specified players (Bowman sets only)

Safe:
  - supports -WhatIf
  - avoids overwriting existing files
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [Parameter(Mandatory = $false)]
  [string]$Root = "C:\Site\GitHub\card-gallery-site\public\cards\baseball\bowman-2025-pro-debut",

  # set to $true if you also want to rename "mitch-voit" -> "mitch-voitr" where applicable
  [switch]$FixMitchVoitTypo
)

$ErrorActionPreference = "Stop"

$folders = @(
  (Join-Path -Path $Root -ChildPath "front-webp")
  (Join-Path -Path $Root -ChildPath "back-webp")
  (Join-Path -Path $Root -ChildPath "thumbs")
)

foreach ($f in $folders) {
  if (-not (Test-Path -LiteralPath $f)) {
    throw "Folder not found: $f"
  }
}

# --- BD number map (extend this as you confirm them) ---
# Key = base filename WITHOUT __front/__back and without extension
# Value = bd-###
$bdMap = @{
  "charlie-condon__colorado-rockies__bowman-draft-2025" = "bd-136"
  "yolfran-castillo__texas-rangers__bowman-draft-2025"  = "bd-107"
  "pico-kohn__new-york-yankees__bowman-draft-2025"      = "bd-52"
  # add more:
  # "jordan-yost__detroit-tigers__bowman-draft-2025"     = "bd-???"
}

# --- 1st Bowman list (Bowman sets only) ---
$firstBowmanKeys = @(
  "pico-kohn__new-york-yankees__bowman-draft-2025",
  "jordan-yost__detroit-tigers__bowman-draft-2025"
)

function Get-BaseKeyFromName {
  param([string]$name)

  # strip extension
  $n = [IO.Path]::GetFileNameWithoutExtension($name)

  # normalize (drop __front/__back if present)
  $n = $n -replace "__(front|back)$", ""

  return $n
}

function Build-NewName {
  param(
    [string]$oldName,
    [string]$folderPath
  )

  $ext = [IO.Path]::GetExtension($oldName)
  $stem = [IO.Path]::GetFileNameWithoutExtension($oldName)

  # Identify side from filename; if missing, infer from folder
  $side = $null
  if ($stem -match "__front$")      { $side = "front" }
  elseif ($stem -match "__back$")   { $side = "back" }
  else {
    if ($folderPath -like "*back-webp*") { $side = "back" } else { $side = "front" }
  }

  # Base key for mapping
  $baseKey = Get-BaseKeyFromName -name $oldName

  # Optional: fix mitch-voit -> mitch-voitr
  if ($FixMitchVoitTypo) {
    $baseKey = $baseKey -replace "^mitch-voit__", "mitch-voitr__"
    $stem    = $stem    -replace "^mitch-voit__", "mitch-voitr__"
  }

  # Only touch Bowman Draft 2025 style files
  if ($baseKey -notmatch "__bowman-draft-2025$") {
    return $null
  }

  $isFirst = $firstBowmanKeys -contains $baseKey

  # If already contains bd-### in the name, preserve it; only inject 1st-bowman if needed
  # pattern example: ...__bowman-draft-2025__bd-136__front
  if ($stem -match "__bd-\d{1,3}__(front|back)$") {
    $newStem = $stem

    if ($isFirst -and ($newStem -notmatch "__1st-bowman__")) {
      $newStem = $newStem -replace "__bowman-draft-2025", "__1st-bowman__bowman-draft-2025"
    }
    return ($newStem + $ext)
  }

  # Lookup BD number
  $bd = $null
  if ($bdMap.ContainsKey($baseKey)) { $bd = $bdMap[$baseKey] }

  # If no BD mapping yet, optionally still add 1st-bowman (but keep name otherwise)
  if (-not $bd) {
    if ($isFirst -and ($stem -notmatch "__1st-bowman__")) {
      $newStem = $stem -replace "__bowman-draft-2025", "__1st-bowman__bowman-draft-2025"
      return ($newStem + $ext)
    }
    return $null
  }

  # Build new base: add 1st-bowman if needed
  $newBase = $baseKey
  if ($isFirst -and ($newBase -notmatch "__1st-bowman__")) {
    $newBase = $newBase -replace "__bowman-draft-2025", "__1st-bowman__bowman-draft-2025"
  }

  $newName = "{0}__{1}__{2}{3}" -f $newBase, $bd, $side, $ext
  return $newName
}

function Rename-InFolder {
  param([string]$folder)

  Write-Host "`n== Scanning: $folder ==" -ForegroundColor Cyan

  Get-ChildItem -LiteralPath $folder -File -Filter *.webp | ForEach-Object {
    $old = $_.Name
    $new = Build-NewName -oldName $old -folderPath $folder

    if (-not $new) { return }
    if ($old -eq $new) { return }

    $oldPath = $_.FullName
    $newPath = Join-Path -Path $folder -ChildPath $new

    if (Test-Path -LiteralPath $newPath) {
      Write-Warning "SKIP (target exists): $old -> $new"
      return
    }

    if ($PSCmdlet.ShouldProcess($oldPath, "Rename to $new")) {
      Rename-Item -LiteralPath $oldPath -NewName $new
      Write-Host "Renamed: $old -> $new" -ForegroundColor Green
    }
  }
}

foreach ($folder in $folders) {
  Rename-InFolder -folder $folder
}

Write-Host "`nDone. Tip: run with -WhatIf first to preview." -ForegroundColor Yellow
