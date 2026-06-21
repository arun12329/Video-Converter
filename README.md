# Universal Video Converter

Batch-convert a folder of videos to **MP4 (HEVC / H.265)** with a single command.
Comes in two flavors that behave identically:

- **`Convert-Videos.ps1`** — PowerShell, for Windows
- **`convert-videos.sh`** — Bash, for Linux

The converter automatically uses your **NVIDIA GPU** (NVENC) when available and
falls back to **CPU encoding** otherwise. Originals are never touched.

---

## Contents

- [Highlights](#highlights)
- [Quick start](#quick-start)
- [Sample output](#sample-output)
- [Options](#options)
- [Examples](#examples)
- [How it works](#how-it-works)
- [Auto-crop: removing black side bars](#auto-crop-removing-black-side-bars)
- [Output layout](#output-layout)
- [Supported input formats](#supported-input-formats)
- [Notes & limitations](#notes--limitations)
- [Troubleshooting](#troubleshooting)

---

## Highlights

| | Feature |
|---|---|
| 🎞️ | Converts 14 common formats to a single MP4 (HEVC) output |
| ⚡ | Automatic **NVIDIA NVENC** hardware encoding when a GPU is detected |
| 🧠 | Falls back to **libx265** CPU encoding automatically |
| 📐 | Upscales sub-1080p videos to 1080p; leaves 1080p/1440p/4K/8K untouched |
| ✂️ | **Auto-detects and removes centered black side bars** (pillarboxed vertical videos) |
| 🔊 | Copies the source audio when it's MP4-compatible (lossless), else re-encodes to AAC |
| 🔄 | Optional rotation (90° / 180° / 270°) |
| ⏩ | Optional speed-up (audio pitch-corrected via chained `atempo`) |
| ♻️ | Skips files that are already converted — safe to re-run |
| 🛡️ | Never modifies or deletes originals |
| 🚀 | `+faststart` for instant web/streaming playback |
| 📋 | Prints a config banner up front: FFmpeg path/version, encoder + GPU name, counts and total size |
| 📊 | Live per-file size & timing, plus a final converted / skipped / failed summary with total space saved |

---

## Quick start

### Windows (PowerShell)

1. [Install FFmpeg](https://ffmpeg.org/download.html) and add it to your `PATH`, then confirm:

   ```powershell
   ffmpeg -version
   ```

2. Run the script against a folder:

   ```powershell
   .\Convert-Videos.ps1 -Folder "D:\Videos"
   ```

### Linux (Bash)

1. Make the script executable:

   ```bash
   chmod +x convert-videos.sh
   ```

2. Run it (FFmpeg is auto-installed if missing — see [Notes](#notes--limitations)):

   ```bash
   ./convert-videos.sh -f /home/user/videos
   ```

---

## Sample output

```text
============================================================
  Universal Video Converter
============================================================
  FFmpeg  : C:\ffmpeg\bin\ffmpeg.exe
  Version : ffmpeg version 8.1.1-full_build ...
  Encoder : hevc_nvenc (GPU: NVIDIA GeForce GTX 1650 SUPER)
  Source  : D:\Videos
  Output  : D:\Videos\converted-videos
  Rotate  : 0 deg
  Speed   : 1x
  Auto-crop: on (removes centered black side bars)
  Videos  : 12 file(s), total 4.30 GB
============================================================

[1/12] Processing: holiday.mov  (1920x1080, 412.80 MB)
  Crop  : none (full-width content)
  -> Done in 0:01:23.  412.80 MB -> 188.05 MB (saved 54%)

[2/12] Processing: reel.mp4  (1920x1080, 96.40 MB)
  Crop  : side bars removed -> 608x1080 (from 1920x1080)
  -> Done in 0:00:21.  96.40 MB -> 22.18 MB (saved 77%)

...

============================================================
  Completed
  Converted  : 11
  Skipped    : 1
  Failed     : 0
  Input size : 3.98 GB
  Output size: 1.71 GB
  Space saved: 2.27 GB (57%)
  Total time : 0:18:44
  Output dir : D:\Videos\converted-videos
============================================================
```

---

## Options

| Action | PowerShell | Bash | Default |
|---|---|---|---|
| Source folder (required) | `-Folder <path>` | `-f <path>` | — |
| Rotation | `-Rotate 0\|90\|180\|270` | `-r 0\|90\|180\|270` | `0` |
| Speed-up factor | `-Speed <number ≥ 1>` | `-s <number ≥ 1>` | `1` |
| Disable auto-crop | `-NoCrop` | `-n` | off (crop on) |
| Help | `Get-Help .\Convert-Videos.ps1` | `-h` | — |

---

## Examples

> Replace the paths with your own. The Bash equivalent is shown beneath each
> PowerShell command.

**Convert a folder (no changes beyond re-encoding):**

```powershell
.\Convert-Videos.ps1 -Folder "D:\Videos"
```
```bash
./convert-videos.sh -f /home/user/videos
```

**Rotate 90° clockwise:**

```powershell
.\Convert-Videos.ps1 -Folder "D:\Videos" -Rotate 90
```
```bash
./convert-videos.sh -f /home/user/videos -r 90
```

**Make a 20× timelapse (video + pitch-corrected audio):**

```powershell
.\Convert-Videos.ps1 -Folder "D:\Videos" -Speed 20
```
```bash
./convert-videos.sh -f /home/user/videos -s 20
```

**Combine rotation and speed:**

```powershell
.\Convert-Videos.ps1 -Folder "D:\Videos" -Rotate 90 -Speed 10
```
```bash
./convert-videos.sh -f /home/user/videos -r 90 -s 10
```

**Disable automatic side-bar cropping:**

```powershell
.\Convert-Videos.ps1 -Folder "D:\Videos" -NoCrop
```
```bash
./convert-videos.sh -f /home/user/videos -n
```

---

## How it works

**Encoder selection**

| Condition | Video codec | Quality settings |
|---|---|---|
| NVIDIA GPU detected | `hevc_nvenc` | `-preset p6 -cq 20` |
| No NVIDIA GPU | `libx265` | `-crf 23 -preset medium` |

**Audio** is kept losslessly when it's already MP4-compatible (`aac`, `mp3`,
`ac3`, `eac3`) by stream-copying it. Otherwise — or whenever you use `-Speed`,
which has to retime the audio — it is re-encoded to **AAC @ 192 kbps**. Videos
with no audio track are written without one.

**Resolution policy** — videos are upscaled to 1080p only when *both* dimensions
are below 1080p; anything 1080p or larger keeps its native resolution. Output
dimensions are forced to even numbers (required by HEVC).

| Original resolution | Output |
|---|---|
| 640×480, 1280×720 | Upscaled to 1080p |
| 1920×1080, 2560×1440 | Kept |
| 3840×2160 (4K), 7680×4320 (8K) | Kept |

**Speed-up** — `atempo` is capped at 2× per instance, so the requested factor is
decomposed into a chain whose product matches it. For example, `-Speed 5`
produces `atempo=2,atempo=2,atempo=1.25`, keeping audio in sync and pitch-correct.

---

## Auto-crop: removing black side bars

Phone and social-media clips are often a **vertical video centered inside a
landscape frame**, padded with wide black bars on the left and right
(pillarboxing). By default the converter detects these bars and crops them away
so the real content fills the frame.

**How detection works**

1. FFmpeg's [`cropdetect`](https://ffmpeg.org/ffmpeg-filters.html#cropdetect)
   filter samples the video's keyframes (fast — it decodes only keyframes across
   the whole file) and reports the bounding box of the non-black content.
2. The crop is applied **only** when it clearly looks like a centered pillarbox:
   - the detected height is essentially unchanged (≥ 95% of the original — so
     top/bottom *letterbox* bars are **not** touched);
   - the detected width is significantly narrower (≤ 90% of the original);
   - real black bars are present on **both** sides.
3. Otherwise the video is converted with no crop, so genuine full-width
   landscape footage is never altered.

After cropping, the normal resolution policy applies: a cropped vertical clip
shorter than 1080p is upscaled to 1080p height (aspect preserved); one that is
already 1080p or taller is kept as-is.

| Input | Detected content | Result |
|---|---|---|
| `1920×1080`, centered vertical video with side bars | `608×1080` | Cropped to **608×1080**, encoded to HEVC |
| `1138×640`, centered vertical video with side bars | `360×640` | Cropped, then upscaled to **608×1080** |
| `3840×2160` true landscape | full width | **No crop** — HEVC convert only |

Use `-NoCrop` (PowerShell) / `-n` (Bash) to turn this off. Detection requires
`ffprobe` (bundled with FFmpeg); if it isn't found, cropping is skipped
automatically.

---

## Output layout

Converted files are written to a `converted-videos` subfolder inside the source
folder. The original extension is folded into the filename to avoid collisions
(e.g. `clip.mov` and `clip.avi` won't overwrite each other):

```text
Videos/
├── movie.mov
├── clip.avi
└── converted-videos/
    ├── movie_mov.mp4
    └── clip_avi.mp4
```

---

## Supported input formats

`mp4` · `avi` · `mov` · `mkv` · `wmv` · `flv` · `webm` · `mpeg` · `mpg` ·
`m4v` · `3gp` · `ts` · `mts` · `m2ts`

Extension matching is case-insensitive (`.MP4` and `.mp4` are both picked up).

---

## Notes & limitations

- **Originals are safe.** The scripts only read source files and write to the
  `converted-videos` folder.
- **Re-runnable.** Files that already exist in `converted-videos` are skipped, so
  you can stop and resume. A failed conversion deletes its partial output so the
  next run retries it.
- **Top-level only.** Subfolders are not processed recursively, so the
  `converted-videos` output folder is never re-scanned or reprocessed.
- **Auto-crop is conservative.** It only removes centered left/right black bars
  and never touches true landscape or letterboxed footage. Disable it with
  `-NoCrop` / `-n` if you don't want any cropping.
- **Linux auto-install.** If FFmpeg is missing, the Bash script tries to install
  it via `apt`, `dnf`, `yum`, `zypper`, or `pacman` using `sudo`. Install FFmpeg
  yourself beforehand if you'd rather not grant that.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `FFmpeg not found` (Windows) | Install FFmpeg and add its `bin` folder to `PATH`, then reopen the terminal. |
| `running scripts is disabled` (Windows) | Allow the script: `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`, then re-run. |
| `Permission denied` (Linux) | Make it executable: `chmod +x convert-videos.sh`. |
| GPU not used | NVENC needs an NVIDIA GPU plus drivers (`nvidia-smi` must work on Linux). The script falls back to CPU automatically. |
| A video was cropped that shouldn't be | Re-run with `-NoCrop` / `-n` to disable auto-crop for that batch. |
| Auto-crop banner says `off (ffprobe not found)` | Install FFmpeg's full build so `ffprobe` is on `PATH`; crop detection needs it. |
| A file shows `FAILED` | Check the FFmpeg output above the summary; the source file may be corrupt or use an unsupported codec. |
