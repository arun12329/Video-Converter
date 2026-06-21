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
# The script prints a configuration banner before it starts, per-file size and
# timing while it works, and a size/savings summary at the end.
#
# Usage:
#   ./convert-videos.sh -f <folder> [-r 0|90|180|270] [-s speed]

set -uo pipefail
export LC_ALL=C   # force '.' as the decimal separator for awk math

FOLDER=""
ROTATE=0
SPEED=1

usage() {
    cat <<'EOF'
Usage:
  ./convert-videos.sh -f <folder> [-r 0|90|180|270] [-s speed]

Options:
  -f <folder>   Folder containing the source videos (required)
  -r <degrees>  Rotate output: 0, 90, 180, or 270 (default: 0)
  -s <speed>    Speed-up factor, e.g. 2 for 2x (default: 1)
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

while getopts "f:r:s:h" opt; do
    case "$opt" in
        f) FOLDER="$OPTARG" ;;
        r) ROTATE="$OPTARG" ;;
        s) SPEED="$OPTARG" ;;
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
# Build the shared video filter
#   - Upscale to 1080p only when BOTH dimensions are below 1080p; otherwise
#     keep the original resolution.
#   - force_divisible_by=2 keeps dimensions even, which HEVC requires.
# ---------------------------------------------------------------------------

VIDEO_FILTER="scale='if(lt(iw,1920)*lt(ih,1080),1920,iw)':'if(lt(iw,1920)*lt(ih,1080),1080,ih)':force_original_aspect_ratio=decrease:force_divisible_by=2"

case "$ROTATE" in
    90)  VIDEO_FILTER="$VIDEO_FILTER,transpose=1" ;;
    180) VIDEO_FILTER="$VIDEO_FILTER,hflip,vflip" ;;
    270) VIDEO_FILTER="$VIDEO_FILTER,transpose=2" ;;
esac

if awk "BEGIN {exit !($SPEED > 1)}"; then
    VIDEO_FILTER="$VIDEO_FILTER,setpts=PTS/$SPEED"
fi

# ---------------------------------------------------------------------------
# Prepare output folder
# ---------------------------------------------------------------------------

OUTPUT_DIR="$FOLDER/converted-videos"
mkdir -p "$OUTPUT_DIR"

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

    echo
    echo "[$COUNT/$TOTAL] Processing: $filename  ($(human_size "$in_size"))"

    CMD=(ffmpeg -hide_banner -y -i "$file" -vf "$VIDEO_FILTER" -c:v "$VIDEO_CODEC")
    CMD+=("${QUALITY_ARGS[@]}")
    if [ -n "$AUDIO_FILTER" ]; then
        CMD+=(-af "$AUDIO_FILTER")
    fi
    CMD+=(-c:a aac -b:a 192k -movflags +faststart "$output")

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
