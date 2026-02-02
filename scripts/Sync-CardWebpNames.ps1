[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [Parameter(Mandatory=$true)]
  [string]$SetRoot,   # e.g. C:\Site\GitHub\card-gallery-site\public\cards\baseball\bowman-2025-pro-debut

  [switch]$FixThumbs, # rename thumbs to match front names
  [switch]$FixBacks,  # rename backs to match front base

  [string]$ReportPath = ""
)

function Get-BaseFromSideName {
  param([Parameter(Mandatory=$true)][string]$Name)

  $n = $Name.ToLowerInvariant()

  if ($n.EndsWith("__front.webp")) { return $Name.Substring(0, $Name.Length - "__front.webp".Length) }
  if ($n.EndsWith("__back.webp"))  { return $Name.Substring(0, $Name.Length - "__back.webp".Length)  }

  return $null
}

function Ensure-UniquePath {
  param([Parameter(Mandatory=$true)][string]$FullPath)

  if (-not (Test-Path -LiteralPath $FullPath)) { return $FullPath }

  $dir  = Split-Path -Parent $FullPath
  $name = [System.IO.Path]::GetFileNameWithoutExtension($FullPath)
  $ext  = [System.IO.Path]::GetExtension($FullPath)

  $i = 1
  while ($true) {
    $cand = Join-Path $dir ("{0}__dup-{1}{2}" -f $name, $i, $ext)
    if (-not (Test-Path -LiteralPath $cand)) { return $cand }
    $i++
  }
}

# Resolve folders
$frontDir = Join-Path $SetRoot "front-webp"
$backDir  = Join-Path $SetRoot "back-webp"
$thumbDir = Join-Path $SetRoot "thumbs"

foreach ($p in @($frontDir,$backDir,$thumbDir)) {
  if (-not (Test-Path -LiteralPath $p)) { throw "Missing folder: $p" }
}

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
  $ReportPath = Join-Path $SetRoot ("name-sync-report_{0}.csv" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
}

# Load files
$fronts = Get-ChildItem -LiteralPath $frontDir -File -Filter "*.webp"
$backs  = Get-ChildItem -LiteralPath $backDir  -File -Filter "*.webp"
$thumbs = Get-ChildItem -LiteralPath $thumbDir -File -Filter "*.webp"

# Index fronts by base (canonical)
$frontByBase = @{}
foreach ($f in $fronts) {
  if ($f.Name.ToLowerInvariant().EndsWith("__front.webp")) {
    $base = Get-BaseFromSideName -Name $f.Name
    if ($base) { $frontByBase[$base.ToLowerInvariant()] = $f }
  }
}

# Index backs by base
$backByBase = @{}
foreach ($b in $backs) {
  if ($b.Name.ToLowerInvariant().EndsWith("__back.webp")) {
    $base = Get-BaseFromSideName -Name $b.Name
    if ($base) { $backByBase[$base.ToLowerInvariant()] = $b }
  }
}

# Index thumbs by exact filename
$thumbByName = @{}
foreach ($t in $thumbs) {
  $thumbByName[$t.Name.ToLowerInvariant()] = $t
}

$results = New-Object System.Collections.Generic.List[object]

# For each front: enforce thumb match + back match
foreach ($kv in $frontByBase.GetEnumerator()) {

  $baseKey = $kv.Key
  $front   = $kv.Value

  $expectedFrontName = $front.Name
  $expectedBackName  = ($front.Name -replace "__front\.webp$", "__back.webp")

  # -----------------------------
  # THUMBS
  # -----------------------------
  if ($thumbByName.ContainsKey($expectedFrontName.ToLowerInvariant())) {

    $thumb = $thumbByName[$expectedFrontName.ToLowerInvariant()]
    $results.Add([pscustomobject]@{
      Base   = $baseKey
      Front  = $front.Name
      Thumb  = $thumb.Name
      Back   = if ($backByBase.ContainsKey($baseKey)) { $backByBase[$baseKey].Name } else { "" }
      Action = "OK_THUMB"
      Note   = "Thumb matches front filename"
    })

  } else {

    # Try to find a thumb whose "base" matches but name differs
    $maybeThumb = $thumbs | Where-Object {
      $tb = Get-BaseFromSideName -Name $_.Name
      $tb -and ($tb.ToLowerInvariant() -eq $baseKey)
    } | Select-Object -First 1

    if ($maybeThumb) {

      $oldThumbPath = $maybeThumb.FullName
      $newThumbPath = Ensure-UniquePath (Join-Path $thumbDir $expectedFrontName)
      $newThumbName = Split-Path -Leaf $newThumbPath

      if ($FixThumbs -and $PSCmdlet.ShouldProcess($oldThumbPath, "Rename thumb to $newThumbName")) {
        Rename-Item -LiteralPath $oldThumbPath -NewName $newThumbName -ErrorAction Stop
        $results.Add([pscustomobject]@{
          Base   = $baseKey
          Front  = $front.Name
          Thumb  = $newThumbName
          Back   = if ($backByBase.ContainsKey($baseKey)) { $backByBase[$baseKey].Name } else { "" }
          Action = "RENAME_THUMB"
          Note   = "Thumb renamed to match front filename"
        })
      } else {
        $results.Add([pscustomobject]@{
          Base   = $baseKey
          Front  = $front.Name
          Thumb  = $maybeThumb.Name
          Back   = if ($backByBase.ContainsKey($baseKey)) { $backByBase[$baseKey].Name } else { "" }
          Action = "MISMATCH_THUMB"
          Note   = "Thumb exists but name doesn't match front (use -FixThumbs)"
        })
      }

    } else {
      $results.Add([pscustomobject]@{
        Base   = $baseKey
        Front  = $front.Name
        Thumb  = ""
        Back   = if ($backByBase.ContainsKey($baseKey)) { $backByBase[$baseKey].Name } else { "" }
        Action = "MISSING_THUMB"
        Note   = "No thumb found for this front"
      })
    }
  }

  # -----------------------------
  # BACKS
  # -----------------------------
  if ($backByBase.ContainsKey($baseKey)) {

    $back = $backByBase[$baseKey]

    if ($back.Name -ieq $expectedBackName) {
      $results.Add([pscustomobject]@{
        Base   = $baseKey
        Front  = $front.Name
        Thumb  = $expectedFrontName
        Back   = $back.Name
        Action = "OK_BACK"
        Note   = "Back matches expected name"
      })
    } else {

      $oldBackPath = $back.FullName
      $newBackPath = Ensure-UniquePath (Join-Path $backDir $expectedBackName)
      $newBackName = Split-Path -Leaf $newBackPath

      if ($FixBacks -and $PSCmdlet.ShouldProcess($oldBackPath, "Rename back to $newBackName")) {
        Rename-Item -LiteralPath $oldBackPath -NewName $newBackName -ErrorAction Stop
        $results.Add([pscustomobject]@{
          Base   = $baseKey
          Front  = $front.Name
          Thumb  = $expectedFrontName
          Back   = $newBackName
          Action = "RENAME_BACK"
          Note   = "Back renamed to match front base"
        })
      } else {
        $results.Add([pscustomobject]@{
          Base   = $baseKey
          Front  = $front.Name
          Thumb  = $expectedFrontName
          Back   = $back.Name
          Action = "MISMATCH_BACK"
          Note   = "Back exists but name doesn't match expected (use -FixBacks)"
        })
      }
    }

  } else {
    $results.Add([pscustomobject]@{
      Base   = $baseKey
      Front  = $front.Name
      Thumb  = $expectedFrontName
      Back   = ""
      Action = "MISSING_BACK"
      Note   = "No back found for this front"
    })
  }

} # <-- closes foreach front

# Orphan backs: back base not found in fronts
foreach ($kv in $backByBase.GetEnumerator()) {
  if (-not $frontByBase.ContainsKey($kv.Key)) {
    $results.Add([pscustomobject]@{
      Base   = $kv.Key
      Front  = ""
      Thumb  = ""
      Back   = $kv.Value.Name
      Action = "ORPHAN_BACK"
      Note   = "Back exists but no matching front in this set folder (maybe moved to other Bowman folder)"
    })
  }
}

# Export report
$results | Sort-Object Action, Front, Back | Export-Csv -NoTypeInformation -LiteralPath $ReportPath
Write-Host "Report written to: $ReportPath"
Write-Host "Dry run: add -WhatIf. To fix: add -FixThumbs and/or -FixBacks."
