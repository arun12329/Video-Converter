<#
.SYNOPSIS
    Batch-convert videos in a folder to MP4 (HEVC / H.265).

.DESCRIPTION
    Scans a folder for common video formats and re-encodes each file into an
    MP4 (HEVC) inside a "converted-videos" subfolder. Uses NVIDIA NVENC
    hardware encoding when an NVIDIA GPU is available, otherwise falls back to
    the libx265 CPU encoder. Videos smaller than 1080p are upscaled to 1080p;
    larger videos keep their resolution. Already-converted files are skipped,
    and original files are never modified.

.PARAMETER Folder
    Path to the folder containing the source videos.

.PARAMETER Rotate
    Rotate the output by 90, 180, or 270 degrees. Default: 0 (no rotation).

.PARAMETER Speed
    Speed-up factor, e.g. 2 for 2x. Must be >= 1. Default: 1 (no change).

.EXAMPLE
    .\Convert-Videos.ps1 -Folder "D:\Videos"

.EXAMPLE
    .\Convert-Videos.ps1 -Folder "D:\Videos" -Rotate 90 -Speed 2
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Folder,

    [ValidateSet(0, 90, 180, 270)]
    [int]$Rotate = 0,

    [ValidateScript({ $_ -ge 1 })]
    [double]$Speed = 1
)

$invariant = [System.Globalization.CultureInfo]::InvariantCulture

# ---------------------------------------------------------------------------
# Validate input folder
# ---------------------------------------------------------------------------

if (-not (Test-Path -LiteralPath $Folder -PathType Container)) {
    Write-Error "Folder not found: $Folder"
    exit 1
}

# ---------------------------------------------------------------------------
# Locate FFmpeg
# ---------------------------------------------------------------------------

$ffmpegCmd = Get-Command ffmpeg -ErrorAction SilentlyContinue

if (-not $ffmpegCmd) {
    Write-Error "FFmpeg not found. Install it and add it to your PATH."
    exit 1
}

$ffmpeg = $ffmpegCmd.Source

# ---------------------------------------------------------------------------
# Choose encoder (NVENC when an NVIDIA GPU is present, else libx265)
# ---------------------------------------------------------------------------

$useNvenc = $false

try {
    $useNvenc = [bool](
        Get-CimInstance Win32_VideoController -ErrorAction Stop |
            Where-Object { $_.Name -match 'NVIDIA' }
    )
}
catch {
    $useNvenc = $false
}

if ($useNvenc) {
    Write-Host "NVIDIA GPU detected -> using hardware encoder (hevc_nvenc)."
    $videoCodec  = 'hevc_nvenc'
    $codecParams = @('-preset', 'p6', '-cq', '20')
}
else {
    Write-Host "No NVIDIA GPU detected -> using CPU encoder (libx265)."
    $videoCodec  = 'libx265'
    $codecParams = @('-crf', '23', '-preset', 'medium')
}

# ---------------------------------------------------------------------------
# Prepare output folder
# ---------------------------------------------------------------------------

$outputFolder = Join-Path $Folder 'converted-videos'

if (-not (Test-Path -LiteralPath $outputFolder)) {
    New-Item -ItemType Directory -Path $outputFolder -ErrorAction Stop | Out-Null
}

# ---------------------------------------------------------------------------
# Build the shared video filter
#   - Upscale to 1080p only when BOTH dimensions are below 1080p; otherwise
#     keep the original resolution.
#   - force_divisible_by=2 keeps dimensions even, which HEVC requires.
# ---------------------------------------------------------------------------

$videoFilters = @(
    "scale='if(lt(iw,1920)*lt(ih,1080),1920,iw)':'if(lt(iw,1920)*lt(ih,1080),1080,ih)':force_original_aspect_ratio=decrease:force_divisible_by=2"
)

switch ($Rotate) {
    90  { $videoFilters += 'transpose=1' }
    180 { $videoFilters += 'hflip,vflip' }
    270 { $videoFilters += 'transpose=2' }
}

if ($Speed -gt 1) {
    $videoFilters += 'setpts=PTS/' + $Speed.ToString($invariant)
}

$videoFilter = $videoFilters -join ','

# ---------------------------------------------------------------------------
# Build the audio filter
#   atempo is limited to 2x per instance, so chain factors whose product
#   equals the requested speed (e.g. 5x -> atempo=2,atempo=2,atempo=1.25).
# ---------------------------------------------------------------------------

function Get-AudioFilter([double]$Factor) {
    if ($Factor -le 1) { return $null }

    $ic        = [System.Globalization.CultureInfo]::InvariantCulture
    $parts     = @()
    $remaining = $Factor

    while ($remaining -gt 2) {
        $parts     += 'atempo=2'
        $remaining /= 2
    }

    $parts += 'atempo=' + $remaining.ToString($ic)
    return ($parts -join ',')
}

$audioFilter = Get-AudioFilter $Speed

# ---------------------------------------------------------------------------
# Collect source files
# ---------------------------------------------------------------------------

$extensions = @(
    '*.mp4', '*.avi',  '*.mov', '*.mkv', '*.wmv', '*.flv', '*.webm',
    '*.mpeg', '*.mpg', '*.m4v', '*.3gp', '*.ts',  '*.mts', '*.m2ts'
)

$files = @(
    foreach ($ext in $extensions) {
        Get-ChildItem -LiteralPath $Folder -Filter $ext -File -ErrorAction SilentlyContinue
    }
)

if ($files.Count -eq 0) {
    Write-Host "No video files found in: $Folder"
    exit 0
}

# ---------------------------------------------------------------------------
# Convert
# ---------------------------------------------------------------------------

$total     = $files.Count
$count     = 0
$converted = 0
$skipped   = 0
$failed    = 0

foreach ($file in $files) {

    $count++

    $outputFile = Join-Path $outputFolder (
        '{0}_{1}.mp4' -f $file.BaseName, $file.Extension.TrimStart('.')
    )

    if (Test-Path -LiteralPath $outputFile) {
        Write-Host "[$count/$total] Skipping (already converted): $($file.Name)"
        $skipped++
        continue
    }

    Write-Host ""
    Write-Host "[$count/$total] Processing: $($file.Name)"

    $ffmpegArgs = @(
        '-hide_banner',
        '-y',
        '-i', $file.FullName,
        '-vf', $videoFilter,
        '-c:v', $videoCodec
    )

    $ffmpegArgs += $codecParams

    if ($audioFilter) {
        $ffmpegArgs += @('-af', $audioFilter)
    }

    $ffmpegArgs += @(
        '-c:a', 'aac',
        '-b:a', '192k',
        '-movflags', '+faststart',
        $outputFile
    )

    & $ffmpeg @ffmpegArgs

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  -> Done."
        $converted++
    }
    else {
        Write-Host "  -> FAILED (ffmpeg exit code $LASTEXITCODE)."
        # Remove the partial output so a re-run will retry this file.
        if (Test-Path -LiteralPath $outputFile) {
            Remove-Item -LiteralPath $outputFile -Force -ErrorAction SilentlyContinue
        }
        $failed++
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "====================================="
Write-Host "Completed"
Write-Host "  Converted: $converted"
Write-Host "  Skipped:   $skipped"
Write-Host "  Failed:    $failed"
Write-Host "  Output:    $outputFolder"
Write-Host "====================================="
