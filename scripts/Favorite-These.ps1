<#
.SYNOPSIS
  Favorites (or unfavorites) cards by renaming matching webp images.

.DESCRIPTION
  Favorite:
    *_front.webp  -> *__fav__.webp
    *_back.webp   -> *__fav__.webp
  Unfavorite (revert):
    *__fav__.webp in front-webp/thumbs -> *_front.webp
    *__fav__.webp in back-webp         -> *_back.webp

  Hardened behavior:
    - Skips gracefully when expected files aren't found
    - Won't double-favorite (skips if already __fav__)
    - Supports -Unfavorite switch
    - Supports -WhatIf / -Confirm via ShouldProcess

.NOTES
  Assumes repo layout:
    .\public\cards\...\front-webp\*.webp
    .\public\cards\...\back-webp\*.webp
    .\public\cards\...\thumbs\*.webp
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
  # Switch to revert favorites back to __front / __back based on folder
  [switch]$Unfavorite,

  # Root of the website repo (defaults to current dir)
  [string]$RepoRoot = (Get-Location).Path,

  # Root where cards live (relative to RepoRoot)
  [string]$CardsRootRelative = "public\cards",

  # Optional: provide IDs on the command line instead of editing the script
  [string[]]$Ids
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$cardsRoot = Join-Path $RepoRoot $CardsRootRelative
if (-not (Test-Path $cardsRoot)) {
  throw "Cards root not found: $cardsRoot"
}

# -----------------------------------------------------------------------------
# EDIT THIS LIST if you don't pass -Ids
# These should be the "base id" WITHOUT __front.webp / __back.webp (same as your output)
# -----------------------------------------------------------------------------
$favorites = @(
  "andrew-mccutchen__pittsburgh-pirates__numbered-02of05__parallel__allen-ginter",
  "dalton-rushing__los-angeles-dodgers__rc__auto__allen-ginter",
  "frank-thomas__chicago-white-sox__auto__numbered-03of99__allen-ginter",
  "freddie-freeman__los-angeles-dodgers__numbered-20of50__parallel-foil__allen-ginter",
  "ketel-marte__arizona-diamondbacks__mini__numbered-07of10__allen-ginter",
  "matt-olson__atlanta-braves__patch__allen-ginter",
  "sam-aldegueri__los-angeles-angels__rc__numbered-01of10__allen-ginter",
  "dylan-crews_washington-nationals__pps-8__planetary-pursuit__topps-cosmic__rc",
  "corbin-carroll__arizona-diamondbacks__base__topps-cosmic",
  "james-wood__washington-nationals__sn-10__stella-nova__rc",
  "ketel-marte__arizona-diamondbacks__base__topps-cosmic",
  "paul-skenes__pittsburgh-pirates__et-16__extraterrestrial-talent",
  "roki-sasaki__los-angeles-dodgers__ub-6__ultraviolet-beam__rc"
)

if ($Ids -and $Ids.Count -gt 0) {
  $favorites = $Ids
}

function Get-ExpectedSideFromFolder {
  param([string]$FullPath)

  $p = $FullPath.ToLowerInvariant()

  if ($p -match "\\back-webp\\") { return "back" }
  # thumbs are always front thumbnails
  if ($p -match "\\thumbs\\")   { return "front" }
  if ($p -match "\\front-webp\\"){ return "front" }

  # Fallback if folders differ: infer from name
  if ($p -match "__back\.webp$")  { return "back" }
  return "front"
}

function Get-FavoriteDestination {
  param(
    [string]$FullName
  )

  # Already favorite?
  if ($FullName -match "__fav__\.webp$") { return $null }

  if ($FullName -match "__front\.webp$") {
    return ($FullName -replace "__front\.webp$", "__fav__.webp")
  }
  if ($FullName -match "__back\.webp$") {
    return ($FullName -replace "__back\.webp$", "__fav__.webp")
  }

  # If it's some other naming, skip gracefully
  return $null
}

function Get-UnfavoriteDestination {
  param(
    [string]$FullName
  )

  if (-not ($FullName -match "__fav__\.webp$")) { return $null }

  $side = Get-ExpectedSideFromFolder -FullPath $FullName
  if ($side -eq "back") {
    return ($FullName -replace "__fav__\.webp$", "__back.webp")
  }
  return ($FullName -replace "__fav__\.webp$", "__front.webp")
}

function Rename-Safely {
  param(
    [Parameter(Mandatory)] [string]$Source,
    [Parameter(Mandatory)] [string]$Destination
  )

  if ($Source -ieq $Destination) {
    Write-Verbose "No-op (same path): $Source"
    return
  }

  if (-not (Test-Path $Source)) {
    Write-Warning "Missing source (skipping): $Source"
    return
  }

  if (Test-Path $Destination) {
    Write-Warning "Destination exists (skipping): $Destination"
    return
  }

  $srcRel = $Source.Replace($RepoRoot.TrimEnd('\') + '\', '')
  $dstRel = $Destination.Replace($RepoRoot.TrimEnd('\') + '\', '')

if ($PSCmdlet.ShouldProcess($Source, "Rename File -> $dstRel")) {
    Rename-Item -LiteralPath $Source -NewName (Split-Path $Destination -Leaf)
    Write-Host "Renamed: $srcRel -> $dstRel"
  } else {
    Write-Host "Renamed: $srcRel -> $dstRel"
  }

}

foreach ($id in $favorites) {
  Write-Host ""
  $modeLabel = if ($Unfavorite) { "Unfavoriting" } else { "Favoriting" }
  Write-Host ("== {0}: {1} ==" -f $modeLabel, $id)


  # Find matching files anywhere under public\cards
  # Favorite mode searches for __front/__back; Unfavorite mode searches for __fav__
  $pattern = if ($Unfavorite) { "${id}__fav__.webp" } else { "${id}__*.webp" }

  $matches = Get-ChildItem -LiteralPath $cardsRoot -Recurse -File -Filter $pattern -ErrorAction SilentlyContinue

  if (-not $matches -or $matches.Count -eq 0) {
    if ($Unfavorite) {
      Write-Warning "No favorite files found for id (skipping): $id"
    } else {
      Write-Warning "No files found for id (skipping): $id"
    }
    continue
  }

  foreach ($m in $matches) {
    # Skip double-favorite quickly in favorite mode
    if (-not $Unfavorite -and $m.FullName -match "__fav__\.webp$") {
      Write-Verbose "Already favorited (skipping): $($m.FullName)"
      continue
    }

    $dest = if ($Unfavorite) { Get-UnfavoriteDestination -FullName $m.FullName }
            else { Get-FavoriteDestination -FullName $m.FullName }

    if (-not $dest) {
      # In favorite mode, only rename __front/__back; in unfavorite mode, only rename __fav__
      Write-Verbose "Not applicable naming (skipping): $($m.FullName)"
      continue
    }

    Rename-Safely -Source $m.FullName -Destination $dest
  }
}

Write-Host ""
Write-Host "Done."
