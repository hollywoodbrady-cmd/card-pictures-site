# Convert-CardsToWebP.ps1
# Converts originals -> webp and generates thumbs
# Folder layout expected under the current folder:
# front-original, front-webp, back-original, back-webp, thumbs

param(
  [int]$Quality = 82,
  [int]$ThumbWidth = 220
)

# --- sanity checks ---
if (-not (Get-Command magick -ErrorAction SilentlyContinue)) {
  throw "ImageMagick 'magick' not found. Install ImageMagick and ensure it's in PATH."
}

$root = (Get-Location).Path

$frontOrig = Join-Path $root "front-original"
$frontWebp = Join-Path $root "front-webp"
$backOrig  = Join-Path $root "back-original"
$backWebp  = Join-Path $root "back-webp"
$thumbsDir = Join-Path $root "thumbs"

# Create output dirs if missing
$dirs = @($frontWebp, $backWebp, $thumbsDir)
foreach ($d in $dirs) { New-Item -ItemType Directory -Force -Path $d | Out-Null }

function Get-ImageFiles($folder) {
  if (-not (Test-Path $folder)) { return @() }
  Get-ChildItem -Path $folder -File |
    Where-Object { $_.Extension -match '^\.(jpg|jpeg|png|tif|tiff|bmp|gif|webp)$' }
}

function Convert-ToWebp {
  param(
    [Parameter(Mandatory)] [string]$InPath,
    [Parameter(Mandatory)] [string]$OutPath,
    [int]$Q
  )

  # Skip if output exists and is newer than input
  if (Test-Path $OutPath) {
    $inTime  = (Get-Item $InPath).LastWriteTimeUtc
    $outTime = (Get-Item $OutPath).LastWriteTimeUtc
    if ($outTime -ge $inTime) { return }
  }

  # Convert with ImageMagick (strip metadata)
  & magick $InPath -strip -quality $Q -define webp:method=6 $OutPath | Out-Null
}

function Make-Thumb {
  param(
    [Parameter(Mandatory)] [string]$InPath,
    [Parameter(Mandatory)] [string]$OutPath,
    [int]$W,
    [int]$Q
  )

  if (Test-Path $OutPath) {
    $inTime  = (Get-Item $InPath).LastWriteTimeUtc
    $outTime = (Get-Item $OutPath).LastWriteTimeUtc
    if ($outTime -ge $inTime) { return }
  }

  # Resize to width, keep aspect, add a tiny sharpening
  & magick $InPath -strip -resize "${W}x" -unsharp 0x0.75+0.75+0.008 -quality $Q -define webp:method=6 $OutPath | Out-Null
}

Write-Host "Root: $root" -ForegroundColor Cyan
Write-Host "Quality: $Quality | ThumbWidth: $ThumbWidth" -ForegroundColor Cyan

# ---- FRONT ----
$frontFiles = Get-ImageFiles $frontOrig
Write-Host "Front originals: $($frontFiles.Count)" -ForegroundColor Green

foreach ($f in $frontFiles) {
  $base = [IO.Path]::GetFileNameWithoutExtension($f.Name)
  $outWebp = Join-Path $frontWebp ($base + ".webp")
  $outThumb = Join-Path $thumbsDir ($base + ".webp")

  Convert-ToWebp -InPath $f.FullName -OutPath $outWebp -Q $Quality
  Make-Thumb     -InPath $f.FullName -OutPath $outThumb -W $ThumbWidth -Q $Quality
}

# ---- BACK ----
$backFiles = Get-ImageFiles $backOrig
Write-Host "Back originals: $($backFiles.Count)" -ForegroundColor Green

foreach ($f in $backFiles) {
  $base = [IO.Path]::GetFileNameWithoutExtension($f.Name)
  $outWebp = Join-Path $backWebp ($base + ".webp")
  Convert-ToWebp -InPath $f.FullName -OutPath $outWebp -Q $Quality
}

Write-Host "Done. Outputs:" -ForegroundColor Cyan
Write-Host "  $frontWebp"
Write-Host "  $backWebp"
Write-Host "  $thumbsDir"
