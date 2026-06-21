# Universal Video Converter (PowerShell & Bash)

## Features

This project converts videos from multiple formats into MP4 using HEVC (H.265).

### Supported Formats

* MP4
* MOV
* AVI
* MKV
* WMV
* FLV
* WEBM
* MPEG
* MPG
* M4V
* 3GP
* TS
* MTS
* M2TS

### Features

✅ Convert all supported video formats to MP4

✅ HEVC / H.265 encoding

✅ Automatic NVIDIA GPU detection

✅ Uses NVIDIA NVENC when available

✅ Automatically falls back to CPU encoding if NVIDIA is unavailable

✅ Upscales videos below 1080p to 1080p

✅ Keeps original resolution for videos larger than 1080p (1440p, 4K, 8K, etc.)

✅ Optional video rotation

✅ Optional video speed increase

✅ Creates a `converted-videos` folder automatically

✅ Skips files that have already been converted

✅ Prevents filename collisions

✅ Optimized MP4 output using Fast Start

---

# Requirements

## Windows

### Install FFmpeg

Download FFmpeg and add it to your PATH.

Verify installation:

```powershell
ffmpeg -version
```

### Run PowerShell Script

```powershell
.\Convert-Videos.ps1 -Folder "D:\Videos"
```

---

## Linux

The Bash version automatically attempts to install FFmpeg if it is not present.

Supported package managers:

* apt
* dnf
* yum
* zypper
* pacman

Make executable:

```bash
chmod +x convert-videos.sh
```

Run:

```bash
./convert-videos.sh -f /home/user/videos
```

---

# Basic Usage

## Windows

```powershell
.\Convert-Videos.ps1 -Folder "D:\Videos"
```

## Linux

```bash
./convert-videos.sh -f /home/user/videos
```

---

# Rotation Options

## Rotate 90°

### Windows

```powershell
.\Convert-Videos.ps1 `
-Folder "D:\Videos" `
-Rotate 90
```

### Linux

```bash
./convert-videos.sh \
-f /home/user/videos \
-r 90
```

---

## Rotate 180°

### Windows

```powershell
.\Convert-Videos.ps1 `
-Folder "D:\Videos" `
-Rotate 180
```

### Linux

```bash
./convert-videos.sh \
-f /home/user/videos \
-r 180
```

---

## Rotate 270°

### Windows

```powershell
.\Convert-Videos.ps1 `
-Folder "D:\Videos" `
-Rotate 270
```

### Linux

```bash
./convert-videos.sh \
-f /home/user/videos \
-r 270
```

---

# Speed Options

## 2x Speed

### Windows

```powershell
.\Convert-Videos.ps1 `
-Folder "D:\Videos" `
-Speed 2
```

### Linux

```bash
./convert-videos.sh \
-f /home/user/videos \
-s 2
```

---

## 5x Speed

### Windows

```powershell
.\Convert-Videos.ps1 `
-Folder "D:\Videos" `
-Speed 5
```

### Linux

```bash
./convert-videos.sh \
-f /home/user/videos \
-s 5
```

---

## 10x Speed

### Windows

```powershell
.\Convert-Videos.ps1 `
-Folder "D:\Videos" `
-Speed 10
```

### Linux

```bash
./convert-videos.sh \
-f /home/user/videos \
-s 10
```

---

## 20x Speed

### Windows

```powershell
.\Convert-Videos.ps1 `
-Folder "D:\Videos" `
-Speed 20
```

### Linux

```bash
./convert-videos.sh \
-f /home/user/videos \
-s 20
```

---

# Rotation + Speed Example

### Windows

```powershell
.\Convert-Videos.ps1 `
-Folder "D:\Videos" `
-Rotate 90 `
-Speed 10
```

### Linux

```bash
./convert-videos.sh \
-f /home/user/videos \
-r 90 \
-s 10
```

---

# Resolution Behavior

| Original Resolution | Output Resolution |
| ------------------- | ----------------- |
| 640×480             | Upscaled          |
| 1280×720            | Upscaled          |
| 1920×1080           | Kept              |
| 2560×1440           | Kept              |
| 3840×2160 (4K)      | Kept              |
| 7680×4320 (8K)      | Kept              |

---

# GPU Acceleration

If an NVIDIA GPU is detected:

```text
HEVC NVENC
```

is used automatically.

Benefits:

* Much faster encoding
* Lower CPU usage
* Ideal for large video collections

If NVIDIA is not available:

```text
libx265
```

CPU encoding is used automatically.

---

# Output Folder

Converted files are stored in:

```text
converted-videos
```

inside the source folder.

Example:

```text
Videos/
├── movie.mov
├── clip.avi
└── converted-videos/
    ├── movie_mov.mp4
    └── clip_avi.mp4
```

---

# Notes

* Original files are never modified.
* Existing converted files are skipped.
* Output files use MP4 container format.
* Audio is encoded as AAC.
* Video is encoded as HEVC/H.265.
* The script does not process subfolders unless recursive support is added.
* The script does not delete original files.

---

# Examples

Convert normally:

```text
Windows:
.\Convert-Videos.ps1 -Folder "D:\Videos"

Linux:
./convert-videos.sh -f /home/user/videos
```

Convert and rotate:

```text
Windows:
.\Convert-Videos.ps1 -Folder "D:\Videos" -Rotate 90

Linux:
./convert-videos.sh -f /home/user/videos -r 90
```

Create a 20x timelapse:

```text
Windows:
.\Convert-Videos.ps1 -Folder "D:\Videos" -Speed 20

Linux:
./convert-videos.sh -f /home/user/videos -s 20
```
