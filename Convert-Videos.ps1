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

    The script prints a configuration banner before it starts, per-file size
    and timing while it works, and a size/savings summary at the end.

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
# Helpers
# ---------------------------------------------------------------------------

function Format-Size([double]$Bytes) {
    $sign = ''
    if ($Bytes -lt 0) { $sign = '-'; $Bytes = -$Bytes }
    if ($Bytes -ge 1GB) { return ('{0}{1:N2} GB' -f $sign, ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0}{1:N2} MB' -f $sign, ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0}{1:N2} KB' -f $sign, ($Bytes / 1KB)) }
    return ('{0}{1} B' -f $sign, [long]$Bytes)
}

# Percentage smaller the output is vs the input (positive = saved space).
function Get-SavedPercent([double]$In, [double]$Out) {
    if ($In -le 0) { return 0 }
    return [math]::Round((1 - ($Out / $In)) * 100)
}

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
    Write-Host ""
    Write-Host "ERROR: FFmpeg was not found on your PATH." -ForegroundColor Red
    Write-Host "Install it from https://ffmpeg.org/download.html and add it to PATH,"
    Write-Host "then reopen the terminal and run this script again."
    exit 1
}

$ffmpeg        = $ffmpegCmd.Source
$ffmpegVersion = (& $ffmpeg -version 2>$null | Select-Object -First 1)

# ---------------------------------------------------------------------------
# Choose encoder (NVENC when an NVIDIA GPU is present, else libx265)
# ---------------------------------------------------------------------------

$gpuName  = $null
$useNvenc = $false

try {
    $nvidia = Get-CimInstance Win32_VideoController -ErrorAction Stop |
        Where-Object { $_.Name -match 'NVIDIA' } |
        Select-Object -First 1

    if ($nvidia) {
        $useNvenc = $true
        $gpuName  = $nvidia.Name
    }
}
catch {
    $useNvenc = $false
}

if ($useNvenc) {
    $encoderLabel = "hevc_nvenc (GPU: $gpuName)"
    $videoCodec   = 'hevc_nvenc'
    $codecParams  = @('-preset', 'p6', '-cq', '20')
}
else {
    $encoderLabel = 'libx265 (CPU)'
    $videoCodec   = 'libx265'
    $codecParams  = @('-crf', '23', '-preset', 'medium')
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

$total           = $files.Count
$totalInputBytes = ($files | Measure-Object -Property Length -Sum).Sum
if (-not $totalInputBytes) { $totalInputBytes = 0 }

# ---------------------------------------------------------------------------
# Configuration banner
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "============================================================"
Write-Host "  Universal Video Converter"
Write-Host "============================================================"
Write-Host ("  FFmpeg  : {0}" -f $ffmpeg)
Write-Host ("  Version : {0}" -f $ffmpegVersion)
Write-Host ("  Encoder : {0}" -f $encoderLabel)
Write-Host ("  Source  : {0}" -f $Folder)
Write-Host ("  Output  : {0}" -f $outputFolder)
Write-Host ("  Rotate  : {0} deg" -f $Rotate)
Write-Host ("  Speed   : {0}x" -f $Speed)
Write-Host ("  Videos  : {0} file(s), total {1}" -f $total, (Format-Size $totalInputBytes))
Write-Host "============================================================"

if ($total -eq 0) {
    Write-Host ""
    Write-Host "No video files found in: $Folder"
    exit 0
}

# ---------------------------------------------------------------------------
# Convert
# ---------------------------------------------------------------------------

$count                = 0
$converted            = 0
$skipped              = 0
$failed               = 0
$convertedInputBytes  = [long]0
$convertedOutputBytes = [long]0

$runStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

foreach ($file in $files) {

    $count++

    $outputFile = Join-Path $outputFolder (
        '{0}_{1}.mp4' -f $file.BaseName, $file.Extension.TrimStart('.')
    )

    if (Test-Path -LiteralPath $outputFile) {
        Write-Host ("[{0}/{1}] Skipping (already converted): {2}" -f $count, $total, $file.Name)
        $skipped++
        continue
    }

    Write-Host ""
    Write-Host ("[{0}/{1}] Processing: {2}  ({3})" -f $count, $total, $file.Name, (Format-Size $file.Length))

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

    $fileStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    & $ffmpeg @ffmpegArgs
    $fileStopwatch.Stop()

    if ($LASTEXITCODE -eq 0) {
        $outLen = (Get-Item -LiteralPath $outputFile).Length
        $saved  = Get-SavedPercent $file.Length $outLen

        Write-Host ("  -> Done in {0}.  {1} -> {2} (saved {3}%)" -f `
            $fileStopwatch.Elapsed.ToString('hh\:mm\:ss'),
            (Format-Size $file.Length),
            (Format-Size $outLen),
            $saved)

        $convertedInputBytes  += $file.Length
        $convertedOutputBytes += $outLen
        $converted++
    }
    else {
        Write-Host ("  -> FAILED (ffmpeg exit code {0})." -f $LASTEXITCODE)
        # Remove the partial output so a re-run will retry this file.
        if (Test-Path -LiteralPath $outputFile) {
            Remove-Item -LiteralPath $outputFile -Force -ErrorAction SilentlyContinue
        }
        $failed++
    }
}

$runStopwatch.Stop()

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "============================================================"
Write-Host "  Completed"
Write-Host ("  Converted  : {0}" -f $converted)
Write-Host ("  Skipped    : {0}" -f $skipped)
Write-Host ("  Failed     : {0}" -f $failed)

if ($converted -gt 0) {
    $savedBytes   = $convertedInputBytes - $convertedOutputBytes
    $savedPercent = Get-SavedPercent $convertedInputBytes $convertedOutputBytes

    Write-Host ("  Input size : {0}" -f (Format-Size $convertedInputBytes))
    Write-Host ("  Output size: {0}" -f (Format-Size $convertedOutputBytes))
    Write-Host ("  Space saved: {0} ({1}%)" -f (Format-Size $savedBytes), $savedPercent)
}

Write-Host ("  Total time : {0}" -f $runStopwatch.Elapsed.ToString('hh\:mm\:ss'))
Write-Host ("  Output dir : {0}" -f $outputFolder)
Write-Host "============================================================"
