# Make-ToppersFromArt.ps1
# Builds topper videos: rotated + blurred playfield video background,
# cab art (left, full height, bottom-justified), flyer (right), and centered
# title cards that cycle logo -> manufacturer -> year with fades.
# Assets are matched by base filename (Popper game name).
# Missing cab/flyer/logo is skipped gracefully; no playfield video = no output.

param(
    [string]$Game = "",   # e.g. -Game "Attack from Mars (Bally 1995)" ; blank = all tables
    [ValidateSet("Full", "Half")]
    [string]$Mode = "Full"  # Full = full-height topper, Half = half-height topper (see $modes)
)

# ---------- CONFIG ----------
$ffmpeg    = "ffmpeg"   # or full path, e.g. C:\Tools\ffmpeg\bin\ffmpeg.exe
$ffprobe   = "ffprobe"  # ships with ffmpeg
$media     = "C:\vPinball\PinUPSystem\POPMedia\Visual Pinball X"
$pfDir     = "$media\PlayField"
$cabDir    = "$media\DMD"        # cab art
$flyerDir  = "$media\GameInfo"   # flyers
$logoDir   = "$media\Logo"       # logos
$wheelDir  = "$media\Wheel"      # wheel images (fallback when cab art or flyer is missing)

$mfrLogoDir = "$PSScriptRoot\ManufacturerLogos"   # optional: Williams.png, Bally.png, Stern.png ... (falls back to text)

# Output size per mode. Layout values below are designed at 720 px tall and scale with the mode's height.
$modes = @{
    Full = @{ W = 1540; H = 720; inset = 0;   out = "Topper_Generated" }
    Half = @{ W = 1920; H = 540; inset = 200; out = "Topper_Generated_Half" }
}
# inset = extra px (at output size) moving cab art and flyer in from the edges toward the center
$W = $modes[$Mode].W; $H = $modes[$Mode].H
$outDir = "$media\$($modes[$Mode].out)"

$pad      = 40                # side padding for cab art / flyer
$cabBoxW  = 560                # cab art: full height, bottom-justified, max this wide
$cabFillHoles = $true          # fill see-through dark areas inside the cab silhouette with black
$cabMaskClose = 3              # gap-sealing passes for the fill (raise if the background leaks in)
$sideBoxW = 520; $sideBoxH = 640   # wheel fallback box
$flyerH   = 576                # flyer height in px (width follows its aspect); was max 640
$flyerRotate = 5               # degrees clockwise (negative = counter-clockwise, 0 = off)
$logoBoxW = 900; $logoBoxH = 420
$blur     = 8

# Title-card cycle (logo -> manufacturer -> year). Manufacturer/year are parsed from
# the game name "Table (Manufacturer Year)". Only the logo shows if the name has no match.
$fps          = 30
$slide        = 4              # seconds each card is on screen (incl. fades)
$fade         = 0.5            # fade in / fade out seconds
$font         = "C:\Windows\Fonts\arialbd.ttf"
$mfrFontSize  = 150
$yearFontSize = 220
$shadowBlur    = 10            # soft drop shadow on year/manufacturer text
$shadowOffset  = 6             # px down-right
$shadowOpacity = 0.9           # 0-1
$textOutline   = 3             # thin dark outline in px (0 = off)
$tmpDir       = Join-Path $env:TEMP "toppers"
$overwrite = [bool]$Game   # single-game test runs always rebuild; full runs skip existing
# ----------------------------

# Scale the 720-px layout to this mode's height
$k = $H / 720
function S($v) { [int][math]::Round($v * $k) }
$pad = (S $pad) + $modes[$Mode].inset; $cabBoxW = S $cabBoxW; $sideBoxW = S $sideBoxW; $sideBoxH = S $sideBoxH; $flyerH = S $flyerH
$logoBoxW = S $logoBoxW; $logoBoxH = S $logoBoxH; $mfrFontSize = S $mfrFontSize; $yearFontSize = S $yearFontSize
$shadowOffset = S $shadowOffset; $textOutline = S $textOutline
$blur = $blur * $k; $shadowBlur = $shadowBlur * $k

$imgExt = @(".png", ".jpg", ".jpeg", ".bmp", ".webp")
New-Item -ItemType Directory -Force -Path $outDir, $tmpDir | Out-Null

# ffmpeg filter path escaping: C:\a\b -> C\:/a/b
function Esc($p) { ($p -replace '\\', '/') -replace ':', '\:' }
# numbers with a '.' decimal regardless of Windows region settings
function N($x) { ([double]$x).ToString([Globalization.CultureInfo]::InvariantCulture) }

function Find-Asset($dir, $name) {
    foreach ($e in $imgExt) {
        $p = Join-Path $dir ($name + $e)
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

# Manufacturer logo lookup. Ignores spaces/punctuation and a trailing "Logo":
#   "Data East" -> DataEastLogo.png, "Alvin G." -> AlvinGLogo.png,
#   "Spooky Pinball" -> Spooky.png (longest filename that the manufacturer starts with).
# Add any oddballs to $mfrAlias (normalized manufacturer -> normalized filename key).
$mfrAlias = @{ "taitodobrasil" = "taitobrazil" }
function NKey($s) { ($s -replace '[^A-Za-z0-9]', '').ToLower() }
$mfrIndex = @{}
if (Test-Path -LiteralPath $mfrLogoDir) {
    Get-ChildItem -LiteralPath $mfrLogoDir -File | Where-Object { $imgExt -contains $_.Extension.ToLower() } | ForEach-Object {
        $k = NKey ($_.BaseName -replace 'Logo$', '')
        if ($k -and -not $mfrIndex.ContainsKey($k)) { $mfrIndex[$k] = $_.FullName }
    }
}
function Find-MfrLogo($mfr) {
    $k = NKey $mfr
    if ($mfrAlias.ContainsKey($k)) { $k = $mfrAlias[$k] }
    if ($mfrIndex.ContainsKey($k)) { return $mfrIndex[$k] }
    $best = $mfrIndex.Keys | Where-Object { $k.StartsWith($_) } | Sort-Object Length -Descending | Select-Object -First 1
    if ($best) { return $mfrIndex[$best] }
    return $null
}

# Trim transparent padding (e.g. logos centered on a 1500x1500 canvas) so they fill the box.
# Uses ffmpeg's bbox on the alpha channel; returns "crop=w:h:x:y," or "" if nothing to trim.
$cropCache = @{}
function Get-AlphaCrop($path) {
    if ($cropCache.ContainsKey($path)) { return $cropCache[$path] }
    $log = & $ffmpeg -hide_banner -i $path -vf "format=rgba,alphaextract,bbox=min_val=8" -frames:v 1 -f null - 2>&1 | Out-String
    $r = if ($log -match 'crop=(\d+:\d+:\d+:\d+)') { "crop=$($Matches[1])," } else { "" }
    $cropCache[$path] = $r
    return $r
}

$pfFilter = if ($Game){ "$Game.mp4" } else { "*.mp4" }
$pfFiles  = Get-ChildItem -LiteralPath $pfDir -Filter $pfFilter
if (-not $pfFiles) { Write-Warning "No playfield video found for '$pfFilter' in $pfDir"; return }

$pfFiles | ForEach-Object {
    $name = $_.BaseName
    $out  = Join-Path $outDir "$name.mp4"
    if ((Test-Path -LiteralPath $out) -and -not $overwrite) { Write-Host "skip (exists): $name"; return }

    $inputs = @("-i", $_.FullName)
    $fc = "[0:v]transpose=1,scale=${W}:${H}:force_original_aspect_ratio=increase,crop=${W}:${H},gblur=sigma=$(N $blur),setsar=1[v0]"
    $last = "v0"; $idx = 1

    $layers = @(
        @{ path = Find-Asset $cabDir   $name; box = "${cabBoxW}:${H}";        pos = "${pad}:H-h"; fill = $cabFillHoles },
        @{ path = Find-Asset $flyerDir $name; box = "-2:${flyerH}";            pos = "W-w-${pad}:(H-h)/2"; rot = $flyerRotate }
    )
    # Missing cab art or flyer -> use the wheel image in that slot (padding trimmed, centered vertically)
    $wheel = Find-Asset $wheelDir $name
    if ($wheel) {
        if (-not $layers[0].path) { $layers[0] = @{ path = $wheel; box = "${sideBoxW}:${sideBoxH}"; pos = "${pad}:(H-h)/2";     trim = $true } }
        if (-not $layers[1].path) { $layers[1] = @{ path = $wheel; box = "${sideBoxW}:${sideBoxH}"; pos = "W-w-${pad}:(H-h)/2"; trim = $true } }
    }

    $used = @()
    foreach ($l in $layers) {
        if (-not $l.path) { continue }
        $inputs += @("-i", $l.path)
        $pre = if ($l.trim) { "format=rgba,$(Get-AlphaCrop $l.path)" } else { "" }
        $post = if ($l.rot) { $a = "$(N $l.rot)*PI/180"; ",format=rgba,rotate=${a}:ow=rotw(${a}):oh=roth(${a}):c=none" } else { "" }
        $src = "[${idx}:v]"
        if ($l.fill) {
            # Cab PNGs with luma-style alpha: build a solid silhouette matte (threshold alpha, close small gaps,
            # flood-fill the outside from a corner, everything else = cab), put the art over black, apply the matte.
            $close = if ($cabMaskClose -gt 0) { ((@("dilation") * $cabMaskClose) + (@("erosion") * $cabMaskClose)) -join "," } else { "null" }
            $mask = "alphaextract,lut=y='if(gt(val,16),255,0)',$close,pad=iw+4:ih+4:2:2,lut=y='if(gt(val,128),255,0)'," +
                    "floodfill=x=0:y=0:s0=-1:d0=128,lut=y='if(eq(val,128),0,255)',crop=iw-4:ih-4:2:2,gblur=sigma=0.8"
            $fc += ";[${idx}:v]format=rgba,split[fa$idx][fb$idx];[fb$idx]$mask[fm$idx]" +
                   ";[fa$idx]premultiply=inplace=1,format=rgb24[fr$idx];[fr$idx][fm$idx]alphamerge[fx$idx]"
            $src = "[fx$idx]"
        }
        $fc += ";${src}${pre}scale=$($l.box):force_original_aspect_ratio=decrease${post}[s$idx]"
        $fc += ";[$last][s$idx]overlay=$($l.pos)[v$idx]"
        $last = "v$idx"; $used += [IO.Path]::GetFileName($l.path); $idx++
    }
    # ---- title cards: logo / manufacturer / year, cycling with fades ----
    $cards = @()
    $logo = Find-Asset $logoDir $name
    if ($logo) { $cards += @{ img = $logo } }
    # "(Manufacturer Year)" anywhere in the name; text after it (e.g. " v600") is ignored
    $mm = [regex]::Matches($name, '\(([^()]*?)\s+(\d{4})\)')
    if ($mm.Count -gt 0) {
        $m = $mm[$mm.Count - 1]
        $mfr = $m.Groups[1].Value.Trim(); $year = $m.Groups[2].Value
        if ($mfr) {
            $mfrImg = Find-MfrLogo $mfr
            if ($mfrImg) { $cards += @{ img = $mfrImg } }
            else {
                # rough auto-fit so long names stay inside the logo box
                $sz = [math]::Min($mfrFontSize, [math]::Floor($logoBoxW / (0.62 * $mfr.Length)))
                $cards += @{ text = $mfr; size = $sz }
            }
        }
        $cards += @{ text = $year; size = $yearFontSize }
    }

    $n = $cards.Count; $cycle = $n * $slide
    $tail = @()   # extra output args (duration trim)

    if ($n -eq 1 -and $cards[0].img) {
        # logo only: static overlay, no cycling
        $inputs += @("-i", $cards[0].img)
        $fc += ";[${idx}:v]format=rgba,$(Get-AlphaCrop $cards[0].img)scale=${logoBoxW}:${logoBoxH}:force_original_aspect_ratio=decrease[lg]"
        $fc += ";[$last][lg]overlay=(W-w)/2:(H-h)/2[tc]"; $last = "tc"
        $used += [IO.Path]::GetFileName($cards[0].img)
    }
    elseif ($n -ge 1) {
        # PASS 1: render ONE cycle of the title cards (with fades) to a clip with alpha
        $cin = @(); $cfc = "color=c=black@0:s=${logoBoxW}x${logoBoxH}:r=${fps}:d=${cycle},format=rgba[b]"
        $cl = "b"; $ci = 0
        for ($i = 0; $i -lt $n; $i++) {
            $c = $cards[$i]
            $S = $i * $slide
            $fades = "fade=t=in:st=$(N $S):d=$(N $fade):alpha=1,fade=t=out:st=$(N ($S + $slide - $fade)):d=$(N $fade):alpha=1"
            if ($c.img) {
                $cin += @("-loop", "1", "-framerate", "$fps", "-t", "$cycle", "-i", $c.img)
                $src = "[${ci}:v]format=rgba,$(Get-AlphaCrop $c.img)scale=${logoBoxW}:${logoBoxH}:force_original_aspect_ratio=decrease"
                $used += [IO.Path]::GetFileName($c.img); $ci++
            } else {
                $tf = Join-Path $tmpDir "card$i.txt"
                [IO.File]::WriteAllText($tf, $c.text)   # UTF-8, no BOM
                # text + soft drop shadow: split the text, turn one copy black, blur it, put the text on top
                $src = "color=c=black@0:s=${logoBoxW}x${logoBoxH}:r=${fps}:d=${cycle},format=rgba," +
                       "drawtext=fontfile='$(Esc $font)':textfile='$(Esc $tf)':expansion=none:fontsize=$($c.size):" +
                       "fontcolor=white:borderw=${textOutline}:bordercolor=black@0.6:x=(w-tw)/2:y=(h-th)/2," +
                       "split[ta$i][tb$i];[tb$i]lutrgb=r=0:g=0:b=0,colorchannelmixer=aa=$(N $shadowOpacity),gblur=sigma=$(N $shadowBlur)[ts$i];" +
                       "[ts$i][ta$i]overlay=-${shadowOffset}:-${shadowOffset}"
                $used += "text '$($c.text)'"
            }
            $cfc += ";$src,$fades[c$i];[$cl][c$i]overlay=(W-w)/2:(H-h)/2:format=auto[k$i]"
            $cl = "k$i"
        }
        $cardsClip = Join-Path $tmpDir "cards.mov"
        & $ffmpeg -hide_banner -loglevel error -y @cin -filter_complex $cfc -map "[$cl]" -c:v qtrle $cardsClip
        if ($LASTEXITCODE -ne 0) { Write-Warning "card render failed: $name"; return }

        # PASS 2: loop the card clip over the topper; trim to whole cycles so it loops cleanly in Popper
        $inputs = @("-stream_loop", "-1") + $inputs   # also loop the playfield video if it's shorter than one cycle
        $inputs += @("-stream_loop", "-1", "-i", $cardsClip)
        $fc += ";[$last][${idx}:v]overlay=(W-w)/2:(H-h)/2:shortest=1[tc]"; $last = "tc"
        $dur = [double]::Parse((& $ffprobe -v error -show_entries format=duration -of csv=p=0 $_.FullName), [Globalization.CultureInfo]::InvariantCulture)
        $tail = @("-t", (N ([math]::Max(1, [math]::Floor($dur / $cycle)) * $cycle)))
    }

    $fc += ";[$last]format=yuv420p[out]"

    Write-Host "build: $name  (layers: $($used -join ', '))"
    & $ffmpeg -hide_banner -loglevel error -y @inputs -filter_complex $fc -map "[out]" @tail `
        -an -c:v libx264 -crf 20 -preset medium -movflags +faststart $out
    if ($LASTEXITCODE -ne 0) { Write-Warning "ffmpeg failed: $name" }
}
