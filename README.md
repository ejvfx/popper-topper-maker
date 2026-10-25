# Make-ToppersFromArt

A PowerShell script that batch-generates topper videos for PinUP Popper from media you already have. It uses ffmpeg to composite each table's playfield video, cab art, flyer and logos into a looping 1540x720 video.

## What it builds

Each topper is built in layers:

| Layer | Source | Placement |
|---|---|---|
| Background | Playfield video | Rotated 90° clockwise, scaled to fill the frame, cropped and blurred |
| Left | Cab art (`DMD` folder) | Full height, bottom-justified, 40 px from the left edge. Holes in the alpha inside the silhouette are filled with black. |
| Right | Flyer (`GameInfo` folder) | 576 px tall, rotated 5° clockwise, vertically centered, 40 px from the right edge |
| Center | Title cards | Cycles game logo → manufacturer → year, 4 s per card with 0.5 s fades |

Fallbacks:
- **No cab art or no flyer:** the table's wheel image takes that slot, with its transparent padding trimmed.
- **No manufacturer logo image:** the manufacturer name is drawn as text.
- **No `(Manufacturer Year)` in the game name:** only the game logo shows, without cycling.
- **No playfield video:** no topper is built.

The output is trimmed to a whole number of card cycles, so it loops cleanly in Popper.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7.
- ffmpeg and ffprobe on your PATH, built with libx264. The gyan.dev builds work; install with `winget install Gyan.FFmpeg`.
- Popper media folders named after the Popper game name.

## Folder layout

All paths are set in the `CONFIG` block at the top of the script.

| Variable | Default | Contents |
|---|---|---|
| `$pfDir` | `POPMedia\Visual Pinball X\PlayField` | Playfield videos (`.mp4`). This folder drives which tables get built. |
| `$cabDir` | `POPMedia\Visual Pinball X\DMD` | Cab art images |
| `$flyerDir` | `POPMedia\Visual Pinball X\GameInfo` | Flyer images |
| `$logoDir` | `POPMedia\Visual Pinball X\Logo` | Game logos, ideally transparent PNGs |
| `$wheelDir` | `POPMedia\Visual Pinball X\Wheel` | Wheel images, used as fallback art |
| `$mfrLogoDir` | `<script folder>\ManufacturerLogos` | Manufacturer logos (optional) |
| `$outDir` | `POPMedia\Visual Pinball X\Topper_Generated` | Output videos |

Images can be `.png`, `.jpg`, `.jpeg`, `.bmp` or `.webp`. Each file must be named exactly like the playfield video, minus the extension. For example:

```
PlayField\Aliens (Original 2020).mp4
DMD\Aliens (Original 2020).png
GameInfo\Aliens (Original 2020).jpg
Logo\Aliens (Original 2020).png
```

Output goes to a separate folder so nothing in your live `Topper` folder is overwritten. Review the results, then copy the ones you want into `POPMedia\Visual Pinball X\Topper`.

## Usage

Run from the folder containing the script, for example `C:\Scripts`.

**Test with one table.** Pass the playfield video name without `.mp4`. A single-game run always overwrites its previous output.

```
powershell -ExecutionPolicy Bypass -File .\Make-ToppersFromArt.ps1 -Game "Aliens (Original 2020)"
```

**Build all tables.** A full run skips any table that already has an output file.

```
powershell -ExecutionPolicy Bypass -File .\Make-ToppersFromArt.ps1
```

**List exact game names:**

```
Get-ChildItem "C:\vPinball\PinUPSystem\POPMedia\Visual Pinball X\PlayField" -Filter *.mp4 | Select-Object -ExpandProperty BaseName
```

The console prints one line per table, listing the layers used:

```
build: Aliens (Original 2020)  (layers: Aliens (Original 2020).png, Aliens (Original 2020).jpg, Aliens (Original 2020).png, OriginalLogo.png, text '2020')
```

The layer order is cab, flyer, game logo, manufacturer, year. A missing entry means that file wasn't found under the exact game name.

**Rebuilding.** To rebuild tables after changing settings, delete their files from `Topper_Generated` and do a full run, or rebuild them one at a time with `-Game`.

**Cancelling.** Press `Ctrl+C` in the PowerShell window. If ffmpeg keeps running, use `taskkill /f /im ffmpeg.exe`. Then delete the half-written output for the table that was building, which is the last `build:` line. A full run would otherwise skip it.

## Sharing toppers

`Export-ToppersForSharing.ps1` copies the generated toppers to a share folder, `Topper_Share`, with names trimmed to the base table. Everything after the last `(Manufacturer Year)` is dropped:

| Generated name | Shared name |
|---|---|
| `Super Straight (Sonic 1977) v600.mp4` | `Super Straight (Sonic 1977).mp4` |
| `Medieval Madness (Williams 1997) VPW 1.2.mp4` | `Medieval Madness (Williams 1997).mp4` |

The files in `Topper_Generated` are never modified. If several versions of a table trim to the same name, the newest one is kept and the others are listed as skipped. Names without a `(Manufacturer Year)` are copied unchanged and listed.

Preview the renames without copying anything:

```
powershell -ExecutionPolicy Bypass -File .\Export-ToppersForSharing.ps1 -Preview
```

Then copy:

```
powershell -ExecutionPolicy Bypass -File .\Export-ToppersForSharing.ps1
```

Author prefixes before the table name, such as `JP's Star Wars (Data East 1992)`, aren't removed. Check the preview list for those.

## Manufacturer and year

These are read from the `(Manufacturer Year)` part of the game name, anywhere in the name. Text after it, such as a version, is ignored:

| Game name | Manufacturer | Year |
|---|---|---|
| `Aliens (Original 2020)` | Original | 2020 |
| `Super Straight (Sonic 1977) v600` | Sonic | 1977 |
| `Medieval Madness (Williams 1997) VPW 1.2` | Williams | 1997 |

### Manufacturer logos

Put transparent PNGs in `ManufacturerLogos\` next to the script. Matching ignores case, spaces, punctuation and a trailing `Logo` in the filename:

| Manufacturer in game name | Matches |
|---|---|
| Bally | `BallyLogo.png` |
| Data East | `DataEastLogo.png` |
| Alvin G. | `AlvinGLogo.png` |
| Chicago Coin | `ChicagoCoinLogo.png` |
| Spooky Pinball | `Spooky.png` |

If there's no exact match, the longest filename the manufacturer name starts with is used. That's how "Spooky Pinball" picks up `Spooky.png`.

For names that don't match, add an entry to `$mfrAlias`. Both sides are lowercase with no spaces or punctuation:

```powershell
$mfrAlias = @{ "taitodobrasil" = "taitobrazil"; "dgottlieb" = "gottlieb" }
```

### Padding trim

Logos are often centered on a large transparent canvas, such as 1500x1500. The script detects the visible area from the alpha channel and crops to it before scaling, so every logo fills the center box. This applies to game logos, manufacturer logos and wheel fallbacks. It only works on transparent padding: a logo with a solid background will show as a box.

## Settings

All settings are in the `CONFIG` block.

| Setting | Default | Effect |
|---|---|---|
| `$W`, `$H` | 1540, 720 | Output resolution |
| `$blur` | 8 | Background blur strength |
| `$pad` | 40 | Distance of cab art and flyer from the frame edges |
| `$cabBoxW` | 560 | Maximum cab art width. Height is always full frame. |
| `$cabFillHoles` | `$true` | Fills see-through dark areas inside the cab silhouette with black (for cab PNGs with luma-style alpha) |
| `$cabMaskClose` | 3 | Gap-sealing passes for the fill. Raise it if the background leaks into the cab. |
| `$flyerH` | 576 | Flyer height. Width follows its aspect ratio. |
| `$flyerRotate` | 5 | Flyer tilt in degrees clockwise. Negative is counter-clockwise; 0 turns it off. |
| `$sideBoxW`, `$sideBoxH` | 520, 640 | Fit box for wheel fallback images |
| `$logoBoxW`, `$logoBoxH` | 900, 420 | Fit box for title cards |
| `$slide` | 4 | Seconds per title card, including fades |
| `$fade` | 0.5 | Fade-in and fade-out length in seconds |
| `$font` | `arialbd.ttf` | Font for manufacturer and year text |
| `$mfrFontSize` | 150 | Manufacturer text size. Long names shrink automatically to fit. |
| `$yearFontSize` | 220 | Year text size |
| `$shadowBlur` | 10 | Text drop shadow softness |
| `$shadowOffset` | 6 | Drop shadow offset down-right, in px |
| `$shadowOpacity` | 0.9 | Drop shadow darkness, from 0 to 1 |
| `$textOutline` | 3 | Dark text outline width in px. 0 turns it off. |
| `$fps` | 30 | Frame rate of the title-card clip |

## How it works

For tables with cycling cards, each topper renders in two ffmpeg passes:

1. **Cards:** One cycle of title cards is rendered with fades to a temporary clip with an alpha channel, `%TEMP%\toppers\cards.mov` (QuickTime Animation).
2. **Composite:** The background, cab art and flyer are composited, then the card clip is looped over them. The playfield video is also looped if it's shorter than one cycle. The result is encoded as H.264 (CRF 20, yuv420p, no audio, faststart) and trimmed to whole cycles.

Tables with only a game logo skip pass 1 and get a static centered overlay.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| A layer is missing from the `build:` line | The filename doesn't exactly match the playfield video name. Watch for extra spaces and version suffixes. |
| No manufacturer or year cards | The game name has no `(Manufacturer Year)` with a 4-digit year. |
| Manufacturer shown as text instead of its logo | No file in `ManufacturerLogos\` matches. Add the file or a `$mfrAlias` entry. |
| A rebuilt table still looks old | A full run skips existing outputs. Delete the file or use `-Game`. |
| The background is sideways | That playfield video is already landscape. Change `transpose=1` to `transpose=2` for counter-clockwise, or remove it for that set. |
| A logo shows as a box | The PNG has a solid background rather than transparency. |
| `ffmpeg failed: <name>` | Rerun that table with `-Game` and change `-loglevel error` to `-loglevel warning` in the script to see details. |

## Limitations

- Playfield videos must be `.mp4`.
- Cab art, flyers, logos and wheels must be still images. Animated or video cab art isn't looped.
- Only the Visual Pinball X media folders are processed. To do another emulator, point `$media` at its `POPMedia` folder.
