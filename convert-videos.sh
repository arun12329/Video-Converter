#!/usr/bin/env bash

set -euo pipefail

FOLDER=""
ROTATE=0
SPEED=1

usage() {
echo "Usage:"
echo "  ./convert-videos.sh -f <folder> [-r 0|90|180|270] [-s speed]"
exit 1
}

while getopts "f:r:s:" opt; do
case $opt in
f) FOLDER="$OPTARG" ;;
r) ROTATE="$OPTARG" ;;
s) SPEED="$OPTARG" ;;
*) usage ;;
esac
done

if [ -z "$FOLDER" ]; then
usage
fi

if [ ! -d "$FOLDER" ]; then
echo "Folder not found: $FOLDER"
exit 1
fi

install_ffmpeg() {

```
if command -v ffmpeg >/dev/null 2>&1; then
    return
fi

echo "FFmpeg not found. Installing..."

if command -v apt >/dev/null 2>&1; then
    sudo apt update
    sudo apt install -y ffmpeg

elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y ffmpeg

elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y ffmpeg

elif command -v zypper >/dev/null 2>&1; then
    sudo zypper install -y ffmpeg

elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -Sy --noconfirm ffmpeg

else
    echo "Unsupported package manager."
    exit 1
fi
```

}

install_ffmpeg

OUTPUT_DIR="$FOLDER/converted-videos"
mkdir -p "$OUTPUT_DIR"

if command -v nvidia-smi >/dev/null 2>&1; then
echo "NVIDIA GPU detected."

```
VIDEO_CODEC="hevc_nvenc"
QUALITY_ARGS=(-preset p6 -cq 20)
```

else
echo "Using CPU encoding."

```
VIDEO_CODEC="libx265"
QUALITY_ARGS=(-crf 23 -preset medium)
```

fi

create_audio_filter() {

```
local speed="$1"

if awk "BEGIN {exit !($speed <= 1)}"; then
    echo ""
    return
fi

local filter=""
local remaining="$speed"

while awk "BEGIN {exit !($remaining > 2)}"; do
    if [ -n "$filter" ]; then
        filter="$filter,"
    fi

    filter="${filter}atempo=2"
    remaining=$(awk "BEGIN {print $remaining/2}")
done

if [ -n "$filter" ]; then
    filter="$filter,"
fi

filter="${filter}atempo=$remaining"

echo "$filter"
```

}

AUDIO_FILTER=$(create_audio_filter "$SPEED")

VIDEO_FILTER="scale='if(lt(iw,1920)*lt(ih,1080),1920,iw)':'if(lt(iw,1920)*lt(ih,1080),1080,ih)':force_original_aspect_ratio=decrease"

case "$ROTATE" in
90)
VIDEO_FILTER="$VIDEO_FILTER,transpose=1"
;;
180)
VIDEO_FILTER="$VIDEO_FILTER,hflip,vflip"
;;
270)
VIDEO_FILTER="$VIDEO_FILTER,transpose=2"
;;
esac

if awk "BEGIN {exit !($SPEED > 1)}"; then
VIDEO_FILTER="$VIDEO_FILTER,setpts=PTS/$SPEED"
fi

shopt -s nullglob

EXTENSIONS=(
"*.mp4"
"*.avi"
"*.mov"
"*.mkv"
"*.wmv"
"*.flv"
"*.webm"
"*.mpeg"
"*.mpg"
"*.m4v"
"*.3gp"
"*.ts"
"*.mts"
"*.m2ts"
)

FILES=()

for ext in "${EXTENSIONS[@]}"; do
for file in "$FOLDER"/$ext; do
[ -f "$file" ] && FILES+=("$file")
done
done

TOTAL=${#FILES[@]}
COUNT=0

for file in "${FILES[@]}"; do

```
COUNT=$((COUNT+1))

filename=$(basename "$file")
basename_noext="${filename%.*}"
extension="${filename##*.}"

output="$OUTPUT_DIR/${basename_noext}_${extension}.mp4"

if [ -f "$output" ]; then
    echo "[$COUNT/$TOTAL] Skipping: $filename"
    continue
fi

echo
echo "[$COUNT/$TOTAL] Processing: $filename"

CMD=(
    ffmpeg
    -y
    -i "$file"
    -vf "$VIDEO_FILTER"
    -c:v "$VIDEO_CODEC"
)

CMD+=("${QUALITY_ARGS[@]}")

if [ -n "$AUDIO_FILTER" ]; then
    CMD+=(-af "$AUDIO_FILTER")
fi

CMD+=(
    -c:a aac
    -b:a 192k
    -movflags +faststart
    "$output"
)

"${CMD[@]}"

echo "Finished."
```

done

echo
echo "========================================"
echo "Completed"
echo "Output Folder:"
echo "$OUTPUT_DIR"
echo "========================================"
