# Export-ToppersForSharing.ps1
# Copies generated toppers to a share folder with names trimmed to the base table:
#   "Super Straight (Sonic 1977) v600.mp4"            -> "Super Straight (Sonic 1977).mp4"
#   "Medieval Madness (Williams 1997) VPW 1.2.mp4"    -> "Medieval Madness (Williams 1997).mp4"
# Everything after the last "(Manufacturer Year)" is dropped. Originals are never touched.
# Output is sorted into a folder per video resolution (Topper_Share\1540x720, Topper_Share\1920x540),
# so filenames stay exactly the Popper game name and can be dropped straight into a Topper folder.
# If several versions trim to the same name, the newest file wins and the rest are listed.
#
# Preview only:  powershell -ExecutionPolicy Bypass -File .\Export-ToppersForSharing.ps1 -Preview
# Copy:          powershell -ExecutionPolicy Bypass -File .\Export-ToppersForSharing.ps1

param([switch]$Preview)

# ---------- CONFIG ----------
$media    = "C:\vPinball\PinUPSystem\POPMedia\Visual Pinball X"
$srcDirs  = @("$media\Topper_Generated", "$media\Topper_Generated_Half")   # missing folders are skipped
$shareDir = "$media\Topper_Share"   # files go into a subfolder per resolution, e.g. Topper_Share\1920x540
$ffprobe  = "ffprobe"
# ----------------------------

$files = $srcDirs | Where-Object { Test-Path -LiteralPath $_ } |
         ForEach-Object { Get-ChildItem -LiteralPath $_ -Filter *.mp4 } | Sort-Object LastWriteTime -Descending
if (-not $files) { Write-Warning "No .mp4 files in: $($srcDirs -join ', ')"; return }

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

    # resolution from the video itself, e.g. "1920x540"
    $res = (& $ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 $f.FullName | Select-Object -First 1)
    if (-not $res) { Write-Warning "Could not read resolution: $name"; continue }
    $res = $res.Trim()

    $key = "$res|$($base.ToLower())"
    if ($taken.ContainsKey($key)) { $dupes += "  [$res] $name  (kept: $($taken[$key]))"; continue }
    $taken[$key] = $name

    $destDir = Join-Path $shareDir $res
    $dest = Join-Path $destDir "$base.mp4"
    if ($Preview) { Write-Host "[$res] $name  ->  $base" }
    else {
        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
        Write-Host "[$res] $(if ($name -ne $base) { "$name  ->  $base" } else { $name })"
    }
    $copied++
}

Write-Host ""
Write-Host "$(if ($Preview) {'Would copy'} else {'Copied'}) $copied file(s) to $shareDir"
if ($dupes)     { Write-Host "`nSkipped (older version of the same table):"; $dupes | ForEach-Object { Write-Host $_ } }
if ($unchanged) { Write-Host "`nNo '(Manufacturer Year)' found - copied with the name unchanged:"; $unchanged | ForEach-Object { Write-Host "  $_" } }
