param(
  [Parameter(Mandatory=$true)]
  [string]$Path,

  # e.g. bowman-draft-2025
  [string]$SetSlug = "bowman-draft-2025",

  [switch]$WhatIf
)

function Slugify([string]$s) {
  $s = $s.ToLowerInvariant()
  $s = $s -replace "[^a-z0-9]+", "-"
  $s = $s.Trim("-")
  $s = $s -replace "-{2,}", "-"
  return $s
}

function CleanWords([string]$s) {
  # keep letters/spaces/hyphen
  $s = $s -replace "[^A-Za-z \-]", " "
  $s = $s -replace "\s{2,}", " "
  return $s.Trim()
}

function Parse-BD([string]$text) {
  $m = [regex]::Match($text, "\bBD[-\s]?(\d{1,3})\b", "IgnoreCase")
  if (!$m.Success) { return $null }
  return ("BD-{0:D3}" -f [int]$m.Groups[1].Value)
}

function Is-1stBowman([string]$text) {
  $t = $text.ToLowerInvariant()
  return ($t -match "\b1st\b" -and $t -match "bowman")
}

function Parse-BackText([string]$text) {
  $lines = $text -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
  # Try to find player: usually ALL CAPS line with 2+ words
  $player = $null
  foreach ($ln in $lines) {
    $cand = CleanWords $ln
    if ($cand.Split(" ").Count -ge 2 -and $cand.Length -le 30) {
      # heuristic: lots of caps in original line
      $letters = ($ln.ToCharArray() | Where-Object { [char]::IsLetter($_) })
      if ($letters.Count -gt 0) {
        $caps = ($letters | Where-Object { [char]::IsUpper($_) }).Count
        if (($caps / $letters.Count) -gt 0.6) {
          $player = (Get-Culture).TextInfo.ToTitleCase($cand.ToLowerInvariant())
          break
        }
      }
    }
  }

  # Team line: something like "PHILADELPHIA PHILLIES - SS"
  $team = $null
  foreach ($ln in $lines) {
    if ($ln -match "\s-\s") {
      $teamPart = ($ln -split "\s-\s")[0]
      $cand = CleanWords $teamPart
      if ($cand.Split(" ").Count -ge 2 -and $cand.Length -le 35) {
        $team = (Get-Culture).TextInfo.ToTitleCase($cand.ToLowerInvariant())
        break
      }
    }
  }

  return [pscustomobject]@{
    Player = $player
    Team   = $team
    BD     = (Parse-BD $text)
    Is1st  = (Is-1stBowman $text)
  }
}

# --- Find python ---
$py = (Get-Command py -ErrorAction SilentlyContinue)?.Source
if (-not $py) { $py = (Get-Command python -ErrorAction SilentlyContinue)?.Source }
if (-not $py) { throw "Python not found. Install Python and ensure 'py' works." }

# --- Validate folder ---
if (-not (Test-Path $Path)) { throw "Path not found: $Path" }

# Get IMG_*.jpg/jpeg sorted
$files = Get-ChildItem -Path $Path -File |
  Where-Object { $_.Name -match "^IMG_\d+\.(jpg|jpeg)$" } |
  Sort-Object Name

if ($files.Count -lt 2) {
  Write-Host "Not enough IMG_ files found in $Path"
  exit 0
}

# We assume pairs: front then back (IMG_0001, IMG_0002)
for ($i=0; $i -lt $files.Count - 1; $i += 2) {
  $front = $files[$i]
  $back  = $files[$i + 1]

  # OCR the BACK (rotated 90°) using python+pytesseract
  $pyCode = @"
from PIL import Image, ImageOps, ImageEnhance
import pytesseract, json, sys

p = r'''$($back.FullName)'''
im = Image.open(p)
# downscale a bit for speed
max_w = 900
if im.width > max_w:
    r = max_w / im.width
    im = im.resize((int(im.width*r), int(im.height*r)))
im = im.convert("L")
im = ImageOps.autocontrast(im)
im = ImageEnhance.Contrast(im).enhance(1.6)

# rotate to make back text readable
im = im.rotate(90, expand=True)

# crop top ~65% (where player/team/bd usually lives)
im = im.crop((0, 0, im.width, int(im.height * 0.65)))

txt = pytesseract.image_to_string(im, config="--psm 6")
print(txt)
"@

  $text = & $py -c $pyCode 2>$null
  if (-not $text) {
    Write-Warning "OCR failed for $($back.Name). Skipping pair."
    continue
  }

  $info = Parse-BackText $text
  if (-not $info.Player -or -not $info.Team -or -not $info.BD) {
    Write-Warning "Could not parse player/team/BD for $($back.Name). Skipping pair."
    continue
  }

  $playerSlug = Slugify $info.Player
  $teamSlug   = Slugify $info.Team
  $bdSlug     = $info.BD.ToLowerInvariant()

  $firstTag = if ($info.Is1st) { "__1st-bowman" } else { "" }

  $newFront = "${playerSlug}__${teamSlug}${firstTag}__${SetSlug}__${bdSlug}__front$($front.Extension.ToLowerInvariant())"
  $newBack  = "${playerSlug}__${teamSlug}${firstTag}__${SetSlug}__${bdSlug}__back$($back.Extension.ToLowerInvariant())"

  $frontTarget = Join-Path -Path $front.DirectoryName -ChildPath $newFront
  $backTarget  = Join-Path -Path $back.DirectoryName  -ChildPath $newBack

  Write-Host "`nPAIR:"
  Write-Host "  FRONT: $($front.Name) -> $newFront"
  Write-Host "  BACK : $($back.Name)  -> $newBack"

  if (-not $WhatIf) {
    Rename-Item -LiteralPath $front.FullName -NewName $newFront -ErrorAction Stop
    Rename-Item -LiteralPath $back.FullName  -NewName $newBack  -ErrorAction Stop
  }
}

Write-Host "`nDone."
