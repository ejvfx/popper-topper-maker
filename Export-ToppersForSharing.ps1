# Export-ToppersForSharing.ps1
# Copies generated toppers to a share folder with names trimmed to the base table:
#   "Super Straight (Sonic 1977) v600.mp4"            -> "Super Straight (Sonic 1977).mp4"
#   "Medieval Madness (Williams 1997) VPW 1.2.mp4"    -> "Medieval Madness (Williams 1997).mp4"
# Everything after the last "(Manufacturer Year)" is dropped. Originals are never touched.
# If several versions trim to the same name, the newest file wins and the rest are listed.
#
# Preview only:  powershell -ExecutionPolicy Bypass -File .\Export-ToppersForSharing.ps1 -Preview
# Copy:          powershell -ExecutionPolicy Bypass -File .\Export-ToppersForSharing.ps1

param([switch]$Preview)

# ---------- CONFIG ----------
$srcDir   = "C:\vPinball\PinUPSystem\POPMedia\Visual Pinball X\Topper_Generated"
$shareDir = "C:\vPinball\PinUPSystem\POPMedia\Visual Pinball X\Topper_Share"
# ----------------------------

$files = Get-ChildItem -LiteralPath $srcDir -Filter *.mp4 | Sort-Object LastWriteTime -Descending
if (-not $files) { Write-Warning "No .mp4 files in $srcDir"; return }
if (-not $Preview) { New-Item -ItemType Directory -Force -Path $shareDir | Out-Null }

$taken = @{}; $copied = 0; $dupes = @(); $unchanged = @()

foreach ($f in $files) {
    $name = $f.BaseName
    $mm = [regex]::Matches($name, '\([^()]*?\s+\d{4}\)')
    if ($mm.Count -gt 0) {
        $m = $mm[$mm.Count - 1]
        $base = $name.Substring(0, $m.Index + $m.Length)
    } else {
        $base = $name; $unchanged += $name
    }
    $base = ($base -replace '\s+', ' ').Trim()

    $key = $base.ToLower()
    if ($taken.ContainsKey($key)) { $dupes += "  $name  (kept: $($taken[$key]))"; continue }
    $taken[$key] = $name

    $dest = Join-Path $shareDir "$base.mp4"
    if ($Preview) { Write-Host "$name  ->  $base" }
    else {
        Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
        if ($name -ne $base) { Write-Host "$name  ->  $base" } else { Write-Host "$name" }
    }
    $copied++
}

Write-Host ""
Write-Host "$(if ($Preview) {'Would copy'} else {'Copied'}) $copied file(s) to $shareDir"
if ($dupes)     { Write-Host "`nSkipped (older version of the same table):"; $dupes | ForEach-Object { Write-Host $_ } }
if ($unchanged) { Write-Host "`nNo '(Manufacturer Year)' found - copied with the name unchanged:"; $unchanged | ForEach-Object { Write-Host "  $_" } }
