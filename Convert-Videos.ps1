param(
    [Parameter(Mandatory = $true)]
    [string]$Folder,

    [ValidateSet(0,90,180,270)]
    [int]$Rotate = 0,

    [double]$Speed = 1
)

# ----------------------------------------------------
# Find FFmpeg
# ----------------------------------------------------

$ffmpegCmd = Get-Command ffmpeg -ErrorAction SilentlyContinue

if (-not $ffmpegCmd) {
    Write-Host ""
    Write-Host "ERROR: FFmpeg not found."
    Write-Host "Install FFmpeg and add it to PATH."
    exit 1
}

$ffmpeg = $ffmpegCmd.Source

# ----------------------------------------------------
# Detect NVIDIA GPU
# ----------------------------------------------------

$useNvenc = $false

try {
    $gpu = Get-CimInstance Win32_VideoController |
        Where-Object { $_.Name -match "NVIDIA" }

    if ($gpu) {
        $useNvenc = $true
    }
}
catch {
}

if ($useNvenc) {
    Write-Host "NVIDIA GPU detected."
    $videoCodec = "hevc_nvenc"
    $codecParams = @(
        "-preset","p6",
        "-cq","20"
    )
}
else {
    Write-Host "No NVIDIA GPU detected."
    Write-Host "Using CPU encoder (libx265)."

    $videoCodec = "libx265"
    $codecParams = @(
        "-crf","23",
        "-preset","medium"
    )
}

# ----------------------------------------------------
# Output folder
# ----------------------------------------------------

$outputFolder = Join-Path $Folder "converted-videos"

if (!(Test-Path $outputFolder)) {
    New-Item `
        -ItemType Directory `
        -Path $outputFolder | Out-Null
}

# ----------------------------------------------------
# Supported extensions
# ----------------------------------------------------

$extensions = @(
    "*.mp4",
    "*.avi",
    "*.mov",
    "*.mkv",
    "*.wmv",
    "*.flv",
    "*.webm",
    "*.mpeg",
    "*.mpg",
    "*.m4v",
    "*.3gp",
    "*.ts",
    "*.mts",
    "*.m2ts"
)

# ----------------------------------------------------
# Collect files
# ----------------------------------------------------

$files = foreach ($ext in $extensions) {
    Get-ChildItem `
        -Path $Folder `
        -Filter $ext `
        -File
}

$total = $files.Count
$count = 0

foreach ($file in $files) {

    $count++

    $outputFile = Join-Path `
        $outputFolder `
        ($file.BaseName + "_" +
         $file.Extension.TrimStart(".") +
         ".mp4")

    if (Test-Path $outputFile) {
        Write-Host ""
        Write-Host "Skipping: $($file.Name)"
        continue
    }

    Write-Host ""
    Write-Host "[$count/$total] Processing $($file.Name)"

    # ------------------------------------------------
    # Scale Filter
    # Upscale only if BOTH dimensions below 1080p
    # ------------------------------------------------

    $filters = @()

    $filters += "scale='if(lt(iw,1920)*lt(ih,1080),1920,iw)':'if(lt(iw,1920)*lt(ih,1080),1080,ih)':force_original_aspect_ratio=decrease"

    # ------------------------------------------------
    # Rotation
    # ------------------------------------------------

    switch ($Rotate) {

        90 {
            $filters += "transpose=1"
        }

        180 {
            $filters += "hflip,vflip"
        }

        270 {
            $filters += "transpose=2"
        }
    }

    # ------------------------------------------------
    # Speed
    # ------------------------------------------------

    if ($Speed -gt 1) {

        $filters += "setpts=PTS/$Speed"

        $audioFilter = "atempo=2"

        $remaining = $Speed / 2

        while ($remaining -gt 2) {
            $audioFilter += ",atempo=2"
            $remaining /= 2
        }

        $audioFilter += ",atempo=$remaining"
    }
    else {
        $audioFilter = $null
    }

    $videoFilter = $filters -join ","

    # ------------------------------------------------
    # Build FFmpeg command
    # ------------------------------------------------

    $args = @(
        "-y",
        "-i",$file.FullName,
        "-vf",$videoFilter,
        "-c:v",$videoCodec
    )

    $args += $codecParams

    if ($audioFilter) {
        $args += @(
            "-af",$audioFilter
        )
    }

    $args += @(
        "-c:a","aac",
        "-b:a","192k",
        "-movflags","+faststart",
        $outputFile
    )

    & $ffmpeg @args

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Finished."
    }
    else {
        Write-Host "FAILED."
    }
}

Write-Host ""
Write-Host "====================================="
Write-Host "Completed"
Write-Host $outputFolder
Write-Host "====================================="
