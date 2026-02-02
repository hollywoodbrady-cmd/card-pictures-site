[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory=$true)]
  [string]$Folder,

  [int]$Start = 3628,
  [int]$End   = 3709,

  [ValidateSet("Scan","Rename")]
  [string]$Mode = "Scan",

  [string]$CsvPath = "$(Join-Path $Folder 'rename_map.csv')"
)

function Get-PythonCmd {
  if (Get-Command py -ErrorAction SilentlyContinue) { return "py" }
  if (Get-Command python -ErrorAction SilentlyContinue) { return "python" }
  if (Get-Command python3 -ErrorAction SilentlyContinue) { return "python3" }
  throw "Python not found. Install Python and reopen PowerShell."
}

function Get-TesseractPath {
  # Most common Winget install locations
  $candidates = @(
    "$env:ProgramFiles\Tesseract-OCR\tesseract.exe",
    "$env:ProgramFiles(x86)\Tesseract-OCR\tesseract.exe"
  )
  foreach ($p in $candidates) {
    if (Test-Path $p) { return $p }
  }

  # If user has it in PATH, this will work too
  $cmd = Get-Command tesseract -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }

  throw "Tesseract not found. Confirm: tesseract --version"
}

$pyCmd = Get-PythonCmd
$tesseractExe = Get-TesseractPath

if (-not (Test-Path $Folder)) {
  throw "Folder not found: $Folder"
}

# Build a list of files IMG_####.JPEG/JPG/PNG within range
$files = @()
for ($i = $Start; $i -le $End; $i++) {
  $num = $i.ToString("0000")
  $patterns = @("IMG_$num.JPEG","IMG_$num.JPG","IMG_$num.PNG","IMG_$num.jpeg","IMG_$num.jpg","IMG_$num.png")
  foreach ($pat in $patterns) {
    $p = Join-Path $Folder $pat
    if (Test-Path $p) { $files += $p; break }
  }
}

if ($files.Count -eq 0) {
  throw "No IMG_$Start..IMG_$End files found in: $Folder"
}

# Python code (runs once) to OCR all images and produce a rename CSV
$pyCode = @'
import os, re, csv, sys
from PIL import Image, ImageOps
import pytesseract

folder = sys.argv[1]
csv_path = sys.argv[2]
tesseract_exe = sys.argv[3]
paths = sys.argv[4:]

pytesseract.pytesseract.tesseract_cmd = tesseract_exe

def slugify(s: str) -> str:
  s = s.strip().lower()
  s = re.sub(r"['’]", "", s)
  s = re.sub(r"[^a-z0-9]+", "-", s)
  s = re.sub(r"-{2,}", "-", s).strip("-")
  return s

def ocr_crop(img: Image.Image, box):
  # box = (left, top, right, bottom) in pixels
  c = img.crop(box)
  c = ImageOps.grayscale(c)
  c = ImageOps.autocontrast(c)
  # Make text thicker
  c = c.resize((c.size[0]*2, c.size[1]*2))
  # OCR config: treat as a single block of text
  txt = pytesseract.image_to_string(c, config="--psm 6")
  return txt

def avg_conf(img: Image.Image, box):
  c = img.crop(box)
  c = ImageOps.grayscale(c)
  c = ImageOps.autocontrast(c)
  c = c.resize((c.size[0]*2, c.size[1]*2))
  data = pytesseract.image_to_data(c, output_type=pytesseract.Output.DICT, config="--psm 6")
  confs = []
  for conf in data.get("conf", []):
    try:
      v = float(conf)
      if v >= 0:
        confs.append(v)
    except:
      pass
  if not confs:
    return ""
  return round(sum(confs)/len(confs), 1)

def pick_name_from_text(txt: str) -> str:
  # Common Bowman-style: player name often appears as 2 words, sometimes 3.
  # We'll take the "best" line with letters and spaces, prefer longer alpha lines.
  lines = [re.sub(r"[^A-Za-z \-]", " ", l).strip() for l in txt.splitlines()]
  lines = [re.sub(r"\s{2,}", " ", l) for l in lines]
  lines = [l for l in lines if len(re.sub(r"[^A-Za-z]", "", l)) >= 6]

  if not lines:
    return ""

  # Prefer 2-3 word lines with mostly letters
  scored = []
  for l in lines:
    words = [w for w in l.split(" ") if w]
    if len(words) == 0: 
      continue
    alpha = sum(len(re.sub(r"[^A-Za-z]", "", w)) for w in words)
    # bonus for 2-3 word names
    bonus = 10 if 2 <= len(words) <= 3 else 0
    scored.append((alpha + bonus, l))

  scored.sort(reverse=True, key=lambda x: x[0])
  best = scored[0][1]
  # If it's super long, keep first 3 words
  words = best.split(" ")
  if len(words) > 3:
    best = " ".join(words[:3])
  return best.strip()

rows = []
for p in paths:
  fn = os.path.basename(p)
  base, ext = os.path.splitext(fn)

  try:
    img = Image.open(p)
  except Exception as e:
    rows.append([fn, "", f"ERROR opening: {e}", ""])
    continue

  w, h = img.size

  # Crop areas:
  # - bottom band for player name
  bottom = (int(w*0.05), int(h*0.72), int(w*0.95), int(h*0.96))
  # - top-left band to detect "1st bowman"
  topleft = (int(w*0.00), int(h*0.00), int(w*0.35), int(h*0.20))

  txt_bottom = ocr_crop(img, bottom)
  txt_top = ocr_crop(img, topleft)

  name = pick_name_from_text(txt_bottom)
  is_1st = "1ST" in txt_top.upper() or "1ST BOWMAN" in txt_top.upper()

  conf = avg_conf(img, bottom)

  # Suggested filename format (you can edit in CSV before renaming):
  # <player>__bowman-draft-2025__front-original__1st-bowman(optional).ext
  # NOTE: We do NOT guess team automatically here; you can add it if you want.
  if name:
    parts = [slugify(name)]
  else:
    parts = [slugify(base)]

  parts += ["bowman-draft-2025", "front-original"]
  if is_1st:
    parts += ["1st-bowman"]

  suggested = "__".join([p for p in parts if p]) + ext.lower()

  rows.append([fn, suggested, (txt_bottom.strip() + "\n---\n" + txt_top.strip()).strip(), conf])

with open(csv_path, "w", newline="", encoding="utf-8") as f:
  w = csv.writer(f)
  w.writerow(["OriginalFile", "NewFile", "OcrText", "AvgConf"])
  w.writerows(rows)

print(f"Wrote CSV: {csv_path} ({len(rows)} rows)")
'@

# Write python file to a temp location
$tmpPy = Join-Path $env:TEMP "ocr_rename_cards.py"
Set-Content -Path $tmpPy -Value $pyCode -Encoding UTF8

if ($Mode -eq "Scan") {
  Write-Host "Scanning OCR -> $CsvPath"
  & $pyCmd $tmpPy $Folder $CsvPath $tesseractExe @($files) | Write-Host
  Write-Host "Open and edit the CSV if needed, then run again with -Mode Rename."
  return
}

# Rename mode
if (-not (Test-Path $CsvPath)) {
  throw "CSV not found: $CsvPath. Run with -Mode Scan first."
}

$map = Import-Csv $CsvPath
foreach ($row in $map) {
  $old = Join-Path $Folder $row.OriginalFile
  $new = Join-Path $Folder $row.NewFile

  if (-not $row.NewFile -or $row.NewFile.Trim() -eq "") { continue }
  if (-not (Test-Path $old)) { continue }

  if ($old -ieq $new) { continue }

  if (Test-Path $new) {
    Write-Warning "Target exists, skipping: $($row.NewFile)"
    continue
  }

  if ($PSCmdlet.ShouldProcess($row.OriginalFile, "Rename to $($row.NewFile)")) {
    Rename-Item -LiteralPath $old -NewName $row.NewFile
  }
}

Write-Host "Done. If you like it, git add/commit/push your changes."
