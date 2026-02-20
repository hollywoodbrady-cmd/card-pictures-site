param(
  [Parameter(Mandatory)] [string] $Sport,
  [Parameter(Mandatory)] [string] $Set,
  [Parameter(Mandatory)] [string] $BaseName,  # everything BEFORE __front/__back, no extension
  [switch] $Unfavorite,
  [switch] $WhatIf
)

$root = "C:\Site\GitHub\card-gallery-site\public\cards"
$setRoot = Join-Path $root (Join-Path $Sport $Set)

$folders = @(
  "front-webp",
  "back-webp",
  "thumbs",
  "front-original",
  "back-original"
)

function Rename-One($dir, $oldName, $newName) {
  $oldPath = Join-Path $dir $oldName
  $newPath = Join-Path $dir $newName
  if (Test-Path $oldPath) {
    Rename-Item -LiteralPath $oldPath -NewName $newName -WhatIf:$WhatIf
    Write-Host "Renamed: $oldName -> $newName"
  }
}

foreach ($f in $folders) {
  $dir = Join-Path $setRoot $f
  if (!(Test-Path $dir)) { continue }

  Get-ChildItem -LiteralPath $dir -File | ForEach-Object {
    $name = $_.Name

    # only act on this card (matches basename and side)
    if ($name -notmatch "^$([regex]::Escape($BaseName))__(front|back)\.") { return }

    $isFav = $name -match "(^|__)fav(__|$)"
    if ($Unfavorite) {
      if (-not $isFav) { return }
      $new = $name -replace "__fav(?=__front|__back)", ""
      Rename-One $dir $name $new
    } else {
      if ($isFav) { return }
      $new = $name -replace "__(front|back)\.", "__fav`__$1."
      Rename-One $dir $name $new
    }
  }
}
