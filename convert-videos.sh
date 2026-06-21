#!/usr/bin/env bash
#
# Batch-convert videos in a folder to MP4 (HEVC / H.265).
#
# Scans a folder for common video formats and re-encodes each file into a
# "converted-videos" subfolder. Uses NVIDIA NVENC when an NVIDIA GPU is
# detected, otherwise falls back to the libx265 CPU encoder. Videos smaller
# than 1080p are upscaled to 1080p; larger videos keep their resolution.
# Already-converted files are skipped, and original files are never modified.
#
# It also auto-detects centered left/right black bars (pillarboxed vertical
# videos) and crops them away before encoding, unless disabled with -n.
#
# The script prints a configuration banner before it starts, per-file size and
# timing while it works, and a size/savings summary at the end.
#
# Usage:
#   ./convert-videos.sh -f <folder> [-r 0|90|180|270] [-s speed] [-n]

set -uo pipefail
export LC_ALL=C   # force '.' as the decimal separator for awk math

FOLDER=""
ROTATE=0
SPEED=1
NOCROP=0

# Black side-bar (pillarbox) detection thresholds. A crop is applied only when
# it looks like a centered vertical video framed by left/right black bars:
#   - height essentially unchanged (side bars, not letterboxing)
#   - width significantly narrower than the original
#   - bars present on BOTH sides (centered)
CROP_LIMIT=24            # cropdetect black threshold (0-255)
CROP_MIN_BAR_PCT=1       # each side bar must be >= 1% of the width
CROP_MAX_WIDTH_PCT=90    # cropped width must be <= 90% of the original
CROP_MIN_WIDTH_PCT=10    # cropped width must be >= 10% (reject garbage)
CROP_MIN_HEIGHT_PCT=95   # cropped height must be >= 95% of the original

usage() {
    cat <<'EOF'
Usage:
  ./convert-videos.sh -f <folder> [-r 0|90|180|270] [-s speed] [-n]

Options:
  -f <folder>   Folder containing the source videos (required)
  -r <degrees>  Rotate output: 0, 90, 180, or 270 (default: 0)
  -s <speed>    Speed-up factor, e.g. 2 for 2x (default: 1)
  -n            Disable automatic black side-bar (pillarbox) cropping
  -h            Show this help
EOF
    exit "${1:-1}"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Human-readable byte size (e.g. 1572864 -> "1.50 MB").
human_size() {
    awk -v b="${1:-0}" 'BEGIN {
        sign = ""
        if (b < 0) { sign = "-"; b = -b }
        split("B KB MB GB TB PB", u, " ")
        i = 1
        while (b >= 1024 && i < 6) { b /= 1024; i++ }
        if (i == 1) printf "%s%d %s", sign, b, u[i]
        else        printf "%s%.2f %s", sign, b, u[i]
    }'
}

# Whole seconds -> H:MM:SS.
format_duration() {
    local s="${1:-0}"
    printf "%d:%02d:%02d" $((s / 3600)) $(((s % 3600) / 60)) $((s % 60))
}

# Percentage smaller the output is vs the input (positive = saved space).
saved_percent() {
    awk -v i="${1:-0}" -v o="${2:-0}" 'BEGIN {
        if (i > 0) printf "%d", (1 - o / i) * 100
        else       printf "0"
    }'
}

# ---------------------------------------------------------------------------
# Parse and validate arguments
# ---------------------------------------------------------------------------

while getopts "f:r:s:nh" opt; do
    case "$opt" in
        f) FOLDER="$OPTARG" ;;
        r) ROTATE="$OPTARG" ;;
        s) SPEED="$OPTARG" ;;
        n) NOCROP=1 ;;
        h) usage 0 ;;
        *) usage ;;
    esac
done

if [ -z "$FOLDER" ]; then
    echo "Error: -f <folder> is required." >&2
    usage
fi

if [ ! -d "$FOLDER" ]; then
    echo "Error: folder not found: $FOLDER" >&2
    exit 1
fi

case "$ROTATE" in
    0|90|180|270) ;;
    *) echo "Error: -r must be 0, 90, 180, or 270 (got: $ROTATE)" >&2; exit 1 ;;
esac

if ! awk "BEGIN {exit !($SPEED > 0)}" 2>/dev/null; then
    echo "Error: -s must be a positive number (got: $SPEED)" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Ensure FFmpeg is available (auto-install on common Linux distros)
# ---------------------------------------------------------------------------

install_ffmpeg() {
    if command -v ffmpeg >/dev/null 2>&1; then
        return
    fi

    echo "FFmpeg not found. Attempting to install..."

    if command -v apt >/dev/null 2>&1; then
        sudo apt update && sudo apt install -y ffmpeg
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y ffmpeg
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y ffmpeg
    elif command -v zypper >/dev/null 2>&1; then
        sudo zypper install -y ffmpeg
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -Sy --noconfirm ffmpeg
    else
        echo "Error: no supported package manager found. Install FFmpeg manually." >&2
        exit 1
    fi
}

install_ffmpeg

if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "Error: FFmpeg is still unavailable after the installation attempt." >&2
    echo "Install it manually from https://ffmpeg.org/download.html" >&2
    exit 1
fi

FFMPEG_BIN=$(command -v ffmpeg)
FFMPEG_VERSION=$(ffmpeg -version 2>/dev/null | head -1)

# ffprobe (ships with FFmpeg) is needed to read dimensions and the audio codec.
# Without it, crop detection is disabled and audio is always re-encoded to AAC.
if command -v ffprobe >/dev/null 2>&1; then
    HAVE_FFPROBE=1
else
    HAVE_FFPROBE=0
fi

CROP_ENABLED=0
if [ "$NOCROP" -eq 0 ] && [ "$HAVE_FFPROBE" -eq 1 ]; then
    CROP_ENABLED=1
fi

# ---------------------------------------------------------------------------
# Choose encoder (NVENC when an NVIDIA GPU is present, else libx265)
# ---------------------------------------------------------------------------

if command -v nvidia-smi >/dev/null 2>&1; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
    ENCODER_LABEL="hevc_nvenc (GPU: ${GPU_NAME:-NVIDIA})"
    VIDEO_CODEC="hevc_nvenc"
    QUALITY_ARGS=(-preset p6 -cq 20)
else
    ENCODER_LABEL="libx265 (CPU)"
    VIDEO_CODEC="libx265"
    QUALITY_ARGS=(-crf 23 -preset medium)
fi

# ---------------------------------------------------------------------------
# Build the audio filter
#   atempo is limited to 2x per instance, so chain factors whose product
#   equals the requested speed (e.g. 5x -> atempo=2,atempo=2,atempo=1.25).
# ---------------------------------------------------------------------------

build_audio_filter() {
    local speed="$1"

    if awk "BEGIN {exit !($speed <= 1)}"; then
        echo ""
        return
    fi

    local filter=""
    local remaining="$speed"

    while awk "BEGIN {exit !($remaining > 2)}"; do
        filter="${filter}atempo=2,"
        remaining=$(awk "BEGIN {print $remaining / 2}")
    done

    echo "${filter}atempo=${remaining}"
}

AUDIO_FILTER=$(build_audio_filter "$SPEED")

# ---------------------------------------------------------------------------
# Probe helpers (require ffprobe)
# ---------------------------------------------------------------------------

# Echo "WIDTH,HEIGHT" of the first video stream (empty if unavailable).
probe_dims() {
    ffprobe -v error -select_streams v:0 \
        -show_entries stream=width,height -of csv=p=0 "$1" 2>/dev/null | head -1
}

# Echo the codec name of the first audio stream (empty if there is no audio).
probe_audio_codec() {
    ffprobe -v error -select_streams a:0 \
        -show_entries stream=codec_name -of csv=p=0 "$1" 2>/dev/null | head -1
}

# Detect centered left/right black bars via cropdetect (keyframe sampling).
# On a valid side-bar crop, echoes "w:h:x:y" and returns 0; otherwise returns 1.
detect_crop() {
    local path="$1" ow="$2" oh="$3"
    [ "$ow" -gt 0 ] && [ "$oh" -gt 0 ] || return 1

    # skip=0 so even a clip with a single keyframe still gets analyzed.
    local detect
    detect=$(ffmpeg -hide_banner -skip_frame nokey -i "$path" -an \
        -vf "cropdetect=limit=${CROP_LIMIT}:round=2:reset=0:skip=0" -f null - 2>&1 \
        | grep -o 'crop=[0-9]*:[0-9]*:[0-9]*:[0-9]*' | tail -1)
    [ -n "$detect" ] || return 1

    local cw ch cx cy
    IFS=: read -r cw ch cx cy <<< "${detect#crop=}"

    # Keep crop offsets even (chroma-safe for yuv420).
    cx=$((cx - cx % 2))
    cy=$((cy - cy % 2))

    local right=$((ow - cx - cw))

    if [ "$ch" -ge $((oh * CROP_MIN_HEIGHT_PCT / 100)) ] \
       && [ "$cw" -le $((ow * CROP_MAX_WIDTH_PCT / 100)) ] \
       && [ "$cw" -ge $((ow * CROP_MIN_WIDTH_PCT / 100)) ] \
       && [ "$cx" -ge $((ow * CROP_MIN_BAR_PCT / 100)) ] \
       && [ "$right" -ge $((ow * CROP_MIN_BAR_PCT / 100)) ]; then
        echo "${cw}:${ch}:${cx}:${cy}"
        return 0
    fi
    return 1
}

# ---------------------------------------------------------------------------
# Build the base video filter (a per-file crop is prepended later)
#   - Upscale to 1080p only when BOTH dimensions are below 1080p; otherwise
#     keep the original resolution. Evaluated AFTER any crop, so a cropped
#     vertical clip below 1080p height is upscaled to 1080p with aspect kept.
#   - force_divisible_by=2 keeps dimensions even, which HEVC requires.
# ---------------------------------------------------------------------------

BASE_VIDEO_FILTER="scale='if(lt(iw,1920)*lt(ih,1080),1920,iw)':'if(lt(iw,1920)*lt(ih,1080),1080,ih)':force_original_aspect_ratio=decrease:force_divisible_by=2"

case "$ROTATE" in
    90)  BASE_VIDEO_FILTER="$BASE_VIDEO_FILTER,transpose=1" ;;
    180) BASE_VIDEO_FILTER="$BASE_VIDEO_FILTER,hflip,vflip" ;;
    270) BASE_VIDEO_FILTER="$BASE_VIDEO_FILTER,transpose=2" ;;
esac

if awk "BEGIN {exit !($SPEED > 1)}"; then
    BASE_VIDEO_FILTER="$BASE_VIDEO_FILTER,setpts=PTS/$SPEED"
fi

# ---------------------------------------------------------------------------
# Prepare output folder
# ---------------------------------------------------------------------------

OUTPUT_DIR="$FOLDER/converted-videos"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR_ABS=$(cd "$OUTPUT_DIR" 2>/dev/null && pwd)

# ---------------------------------------------------------------------------
# Collect source files (case-insensitive extension match)
# ---------------------------------------------------------------------------

shopt -s nullglob nocaseglob

EXTENSIONS=(mp4 avi mov mkv wmv flv webm mpeg mpg m4v 3gp ts mts m2ts)

FILES=()
TOTAL_INPUT_BYTES=0
for ext in "${EXTENSIONS[@]}"; do
    for file in "$FOLDER"/*."$ext"; do
        [ -f "$file" ] || continue
        FILES+=("$file")
        TOTAL_INPUT_BYTES=$((TOTAL_INPUT_BYTES + $(wc -c < "$file")))
    done
done

shopt -u nocaseglob

TOTAL=${#FILES[@]}

# ---------------------------------------------------------------------------
# Configuration banner
# ---------------------------------------------------------------------------

echo
echo "============================================================"
echo "  Universal Video Converter"
echo "============================================================"
echo "  FFmpeg  : $FFMPEG_BIN"
echo "  Version : $FFMPEG_VERSION"
echo "  Encoder : $ENCODER_LABEL"
echo "  Source  : $FOLDER"
echo "  Output  : $OUTPUT_DIR"
echo "  Rotate  : ${ROTATE} deg"
echo "  Speed   : ${SPEED}x"
if [ "$CROP_ENABLED" -eq 1 ]; then
    echo "  Auto-crop: on (removes centered black side bars)"
elif [ "$NOCROP" -eq 1 ]; then
    echo "  Auto-crop: off (-n)"
else
    echo "  Auto-crop: off (ffprobe not found)"
fi
echo "  Videos  : $TOTAL file(s), total $(human_size "$TOTAL_INPUT_BYTES")"
echo "============================================================"

if [ "$TOTAL" -eq 0 ]; then
    echo
    echo "No video files found in: $FOLDER"
    exit 0
fi

# ---------------------------------------------------------------------------
# Convert
# ---------------------------------------------------------------------------

COUNT=0
CONVERTED=0
SKIPPED=0
FAILED=0
CONVERTED_IN_BYTES=0
CONVERTED_OUT_BYTES=0

RUN_START=$(date +%s)

for file in "${FILES[@]}"; do

    # Defensive: never reprocess a file that lives in the output folder.
    this_dir=$(cd "$(dirname "$file")" 2>/dev/null && pwd)
    if [ -n "$OUTPUT_DIR_ABS" ] && [ "$this_dir" = "$OUTPUT_DIR_ABS" ]; then
        continue
    fi

    COUNT=$((COUNT + 1))

    filename=$(basename "$file")
    basename_noext="${filename%.*}"
    extension="${filename##*.}"
    output="$OUTPUT_DIR/${basename_noext}_${extension}.mp4"

    if [ -f "$output" ]; then
        echo "[$COUNT/$TOTAL] Skipping (already converted): $filename"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    in_size=$(wc -c < "$file")

    # Probe dimensions and audio codec (needed for crop + audio decisions).
    ow=0; oh=0; acodec=""; probed=0
    if [ "$HAVE_FFPROBE" -eq 1 ]; then
        dims=$(probe_dims "$file")
        if [ -n "$dims" ]; then
            ow=${dims%,*}; oh=${dims#*,}
        fi
        [[ "$ow" =~ ^[0-9]+$ ]] || ow=0
        [[ "$oh" =~ ^[0-9]+$ ]] || oh=0
        acodec=$(probe_audio_codec "$file")
        probed=1
    fi

    dim_label=""
    [ "$ow" -gt 0 ] && dim_label="${ow}x${oh}, "

    echo
    echo "[$COUNT/$TOTAL] Processing: $filename  (${dim_label}$(human_size "$in_size"))"

    # --- Detect and remove centered black side bars (pillarbox) ---
    crop_region=""
    if [ "$CROP_ENABLED" -eq 1 ]; then
        crop_region=$(detect_crop "$file" "$ow" "$oh") || crop_region=""
        if [ -n "$crop_region" ]; then
            IFS=: read -r cw ch _ _ <<< "$crop_region"
            echo "  Crop  : side bars removed -> ${cw}x${ch} (from ${ow}x${oh})"
        else
            echo "  Crop  : none (full-width content)"
        fi
    fi

    # --- Video filter: optional per-file crop, then the shared base filter ---
    if [ -n "$crop_region" ]; then
        vf="crop=${crop_region},${BASE_VIDEO_FILTER}"
    else
        vf="$BASE_VIDEO_FILTER"
    fi

    # --- Audio: re-encode when speeding up; else copy if MP4-compatible ---
    AUDIO_ARGS=()
    if [ -n "$AUDIO_FILTER" ]; then
        AUDIO_ARGS=(-af "$AUDIO_FILTER" -c:a aac -b:a 192k)
    elif [ "$probed" -eq 0 ]; then
        AUDIO_ARGS=(-c:a aac -b:a 192k)          # can't probe -> safe re-encode
    elif [ -z "$acodec" ]; then
        AUDIO_ARGS=(-an)                         # no audio stream
    elif [[ " aac mp3 ac3 eac3 " == *" $acodec "* ]]; then
        AUDIO_ARGS=(-c:a copy)                   # already MP4-compatible
    else
        AUDIO_ARGS=(-c:a aac -b:a 192k)          # re-encode to AAC
    fi

    CMD=(ffmpeg -hide_banner -y -i "$file" -vf "$vf" -c:v "$VIDEO_CODEC")
    CMD+=("${QUALITY_ARGS[@]}")
    CMD+=("${AUDIO_ARGS[@]}")
    CMD+=(-movflags +faststart "$output")

    file_start=$(date +%s)
    if "${CMD[@]}"; then
        file_end=$(date +%s)
        out_size=$(wc -c < "$output")
        echo "  -> Done in $(format_duration $((file_end - file_start)))."\
"  $(human_size "$in_size") -> $(human_size "$out_size") (saved $(saved_percent "$in_size" "$out_size")%)"
        CONVERTED=$((CONVERTED + 1))
        CONVERTED_IN_BYTES=$((CONVERTED_IN_BYTES + in_size))
        CONVERTED_OUT_BYTES=$((CONVERTED_OUT_BYTES + out_size))
    else
        echo "  -> FAILED."
        rm -f "$output"   # drop the partial output so a re-run retries it
        FAILED=$((FAILED + 1))
    fi
done

RUN_END=$(date +%s)

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo
echo "============================================================"
echo "  Completed"
echo "  Converted  : $CONVERTED"
echo "  Skipped    : $SKIPPED"
echo "  Failed     : $FAILED"

if [ "$CONVERTED" -gt 0 ]; then
    saved_bytes=$((CONVERTED_IN_BYTES - CONVERTED_OUT_BYTES))
    echo "  Input size : $(human_size "$CONVERTED_IN_BYTES")"
    echo "  Output size: $(human_size "$CONVERTED_OUT_BYTES")"
    echo "  Space saved: $(human_size "$saved_bytes") ($(saved_percent "$CONVERTED_IN_BYTES" "$CONVERTED_OUT_BYTES")%)"
fi

echo "  Total time : $(format_duration $((RUN_END - RUN_START)))"
echo "  Output dir : $OUTPUT_DIR"
echo "============================================================"
