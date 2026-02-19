param(
  [switch]$WhatIf
)

$root = "C:\Site\GitHub\card-gallery-site\public\psa"

$dirs = @(
  (Join-Path $root "front-webp"),
  (Join-Path $root "thumbs"),
  (Join-Path $root "back-webp")
)

# Explicit mapping (safe + predictable)
$map = @{
  "elly-de-la-cruz_2024_topps_all-star-fame_#141_front.webp" =
    "elly-de-la-cruz__2024-topps-all-star-fame__141__psa__front.webp"

  "jackson_merrill_2024_topps_chrome_update_x-fractor_#usc153_front.webp" =
    "jackson-merrill__2024-topps-chrome-update__x-fractor__usc153__psa__front.webp"

  "slade_caldwell_2025_bowman_chr.pros_reptilian-refractor_#bcp-21_front.webp" =
    "slade-caldwell__2025-bowman-chrome-prospects__reptilian-refractor__bcp-21__psa__front.webp"

  "yordan-alvarez_2020_topps-series-1_#276_front.webp" =
    "yordan-alvarez__2020-topps-series-1__276__psa__front.webp"
}

function Rename-InDir {
  param(
    [string]$Dir,
    [hashtable]$Map,
    [switch]$WhatIf
  )

  if (-not (Test-Path $Dir)) { return }

  foreach ($old in $Map.Keys) {
    $new = $Map[$old]

    $oldPath = Join-Path $Dir $old
    if (Test-Path $oldPath) {
      $newPath = Join-Path $Dir $new
      Write-Host "[$Dir] $old -> $new"
      Rename-Item -LiteralPath $oldPath -NewName $new -WhatIf:$WhatIf
    }
  }
}

foreach ($d in $dirs) {
  Rename-InDir -Dir $d -Map $map -WhatIf:$WhatIf
}
