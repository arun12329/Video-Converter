# Video Converter

Converts videos to MP4 using HEVC/H.265.

Supports:

- MP4
- MOV
- AVI
- MKV
- WMV
- FLV
- WEBM
- TS
- MTS
- M2TS
- MPEG
- MPG
- M4V
- 3GP

---

## Requirements

Install FFmpeg.

Verify:

```powershell
ffmpeg -version
```

---

## Basic Conversion

```powershell
.\Convert-Videos.ps1 -Folder "D:\Videos"
```

---

## Rotate 90 Degrees

```powershell
.\Convert-Videos.ps1 `
-Folder "D:\Videos" `
-Rotate 90
```

---

## Rotate 180 Degrees

```powershell
.\Convert-Videos.ps1 `
-Folder "D:\Videos" `
-Rotate 180
```

---

## Rotate 270 Degrees

```powershell
.\Convert-Videos.ps1 `
-Folder "D:\Videos" `
-Rotate 270
```

---

## Speed Up 5x

```powershell
.\Convert-Videos.ps1 `
-Folder "D:\Videos" `
-Speed 5
```

---

## Speed Up 10x

```powershell
.\Convert-Videos.ps1 `
-Folder "D:\Videos" `
-Speed 10
```

---

## Speed Up 20x

```powershell
.\Convert-Videos.ps1 `
-Folder "D:\Videos" `
-Speed 20
```

---

## Rotate and Speed Up

```powershell
.\Convert-Videos.ps1 `
-Folder "D:\Videos" `
-Rotate 90 `
-Speed 10
```

---

## Output Folder

Converted videos are saved to:

```text
converted-videos
```

inside the source folder.

---

## GPU Acceleration

If NVIDIA GPU is detected:

```text
hevc_nvenc
```

is used automatically.

Otherwise:

```text
libx265
```

CPU encoding is used automatically.
