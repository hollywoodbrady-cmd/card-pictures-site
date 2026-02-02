<#
Renames files based on a CSV mapping (PowerShell 5.1 compatible).

Expected CSV columns (case-insensitive):
  OldName, NewName

Notes:
- If NewName has no extension, the old file's extension is preserved.
- Invalid filename characters are replaced with '-'.
- If the target name already exists, a unique "__dup-N" suffix is added.
- Supports -WhatIf.

Examples:
  .\Rename-FromCsv.ps1 -CsvPath .\rename-map.csv -Folder "..\public\cards\...\front-original" -WhatIf
  .\Rename-FromCsv.ps1 -CsvPath .\rename-map.csv -Folder "..\public\cards\...\front-original"
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [Parameter(Mandatory=$false)]
  [string]$CsvPath = ".\rename-map.csv",

  [Parameter(Mandatory=$false)]
  [string]$Folder = ".",

  [switch]$Recurse,

  [switch]$Force
)

function Get-UniqueTargetPath {
  param([Parameter(Mandatory=$true)][string]$TargetPath)

  if (-not (Test-Path -LiteralPath $TargetPath)) { return $TargetPath }

  $dir  = Split-Path -Parent $TargetPath
  $name = [System.IO.Path]::GetFileNameWithoutExtension($TargetPath)
  $ext  = [System.IO.Path]::GetExtension($TargetPath)

  $i = 1
  while ($true) {
    $candidate = Join-Path $dir ("{0}__dup-{1}{2}" -f $name, $i, $ext)
    if (-not (Test-Path -LiteralPath $candidate)) { return $candidate }
    $i++
  }
}

function Normalize-NewName {
  param(
    [Parameter(Mandatory=$true)][string]$NewName,
    [Parameter(Mandatory=$true)][string]$OldName
  )

  $new = ([string]$NewName).Trim()

  # If NewName has no extension, keep the old extension
  $newExt = [System.IO.Path]::GetExtension($new)
  if ([string]::IsNullOrWhiteSpace($newExt)) {
    $oldExt = [System.IO.Path]::GetExtension($OldName)
    $new = $new + $oldExt
  }

  # Remove invalid filename chars
  $invalid = [Regex]::Escape(([string][System.IO.Path]::GetInvalidFileNameChars()))
  $new = [Regex]::Replace($new, "[$invalid]", "-")

  # Collapse whitespace
  $new = ($new -replace "\s+", " ").Trim()

  return $new
}

if (-not (Test-Path -LiteralPath $CsvPath)) { throw "CSV not found: $CsvPath" }
if (-not (Test-Path -LiteralPath $Folder))  { throw "Folder not found: $Folder" }

$rows = Import-Csv -LiteralPath $CsvPath
if (-not $rows -or $rows.Count -eq 0) { throw "No rows found in CSV: $CsvPath" }

# Build lookup of existing files (optional recurse)
$files = Get-ChildItem -LiteralPath $Folder -File -Recurse:$Recurse
$fileByName = @{}
foreach ($f in $files) { $fileByName[$f.Name] = $f.FullName }

$results = New-Object System.Collections.Generic.List[object]
$plannedTargets = @{}  # prevent duplicates within the same run

foreach ($r in $rows) {
  $oldName = ([string]$r.OldName).Trim()
  $newNameRaw = ([string]$r.NewName).Trim()

  if ([string]::IsNullOrWhiteSpace($oldName)) {
    $results.Add([pscustomobject]@{ OldName=""; NewName=""; Status="SKIP"; Note="Missing OldName in CSV row" })
    continue
  }
  if ([string]::IsNullOrWhiteSpace($newNameRaw)) {
    $results.Add([pscustomobject]@{ OldName=$oldName; NewName=""; Status="SKIP"; Note="Missing NewName in CSV row" })
    continue
  }
  if (-not $fileByName.ContainsKey($oldName)) {
    $results.Add([pscustomobject]@{ OldName=$oldName; NewName=$newNameRaw; Status="MISSING"; Note="Source file not found in folder" })
    continue
  }

  $srcPath = $fileByName[$oldName]
  $newName = Normalize-NewName -NewName $newNameRaw -OldName $oldName
  $targetPath = Join-Path (Split-Path -Parent $srcPath) $newName

  # Prevent collisions caused by duplicates inside the CSV itself
  $targetKey = $targetPath.ToLowerInvariant()
  if ($plannedTargets.ContainsKey($targetKey)) {
    $targetPath = Get-UniqueTargetPath -TargetPath $targetPath
  }

  # Prevent collisions with files already on disk
  if (Test-Path -LiteralPath $targetPath) {
    if ($Force) {
      # Even with -Force, avoid overwriting by choosing a unique name
      $targetPath = Get-UniqueTargetPath -TargetPath $targetPath
    } else {
      $targetPath = Get-UniqueTargetPath -TargetPath $targetPath
    }
  }

  $plannedTargets[$targetPath.ToLowerInvariant()] = $true
  $finalNewName = Split-Path -Leaf $targetPath

  if ($PSCmdlet.ShouldProcess($srcPath, "Rename to $finalNewName")) {
    try {
      Rename-Item -LiteralPath $srcPath -NewName $finalNewName -Force:$Force -ErrorAction Stop
      $results.Add([pscustomobject]@{ OldName=$oldName; NewName=$finalNewName; Status="RENAMED"; Note="" })
    } catch {
      $results.Add([pscustomobject]@{ OldName=$oldName; NewName=$finalNewName; Status="ERROR"; Note=$_.Exception.Message })
    }
  } else {
    $results.Add([pscustomobject]@{ OldName=$oldName; NewName=$finalNewName; Status="WHATIF"; Note="" })
  }
}

$logPath = Join-Path (Split-Path -Parent (Resolve-Path $CsvPath)) ("rename-log_{0}.csv" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
$results | Export-Csv -NoTypeInformation -LiteralPath $logPath
Write-Host "Done. Log written to: $logPath"
