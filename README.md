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
- [Options](#options)
- [Examples](#examples)
- [How it works](#how-it-works)
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
| 🔄 | Optional rotation (90° / 180° / 270°) |
| ⏩ | Optional speed-up (audio pitch-corrected via chained `atempo`) |
| ♻️ | Skips files that are already converted — safe to re-run |
| 🛡️ | Never modifies or deletes originals |
| 🚀 | `+faststart` for instant web/streaming playback |
| 📊 | Prints a converted / skipped / failed summary at the end |

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

## Options

| Action | PowerShell | Bash | Default |
|---|---|---|---|
| Source folder (required) | `-Folder <path>` | `-f <path>` | — |
| Rotation | `-Rotate 0\|90\|180\|270` | `-r 0\|90\|180\|270` | `0` |
| Speed-up factor | `-Speed <number ≥ 1>` | `-s <number ≥ 1>` | `1` |
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

---

## How it works

**Encoder selection**

| Condition | Video codec | Quality settings |
|---|---|---|
| NVIDIA GPU detected | `hevc_nvenc` | `-preset p6 -cq 20` |
| No NVIDIA GPU | `libx265` | `-crf 23 -preset medium` |

Audio is always re-encoded to **AAC @ 192 kbps**.

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
- **Top-level only.** Subfolders are not processed recursively.
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
| A file shows `FAILED` | Check the FFmpeg output above the summary; the source file may be corrupt or use an unsupported codec. |
