#!/usr/bin/env bash
# Captures 50 frames at 5fps; defaults to observed 800x448 YUYV webcam mode.
set -euo pipefail
CAMERA="${CAMERA:-/dev/video0}"
CAPTURE_WIDTH="${CAPTURE_WIDTH:-800}"
CAPTURE_HEIGHT="${CAPTURE_HEIGHT:-448}"
OUTPUT_WIDTH="${OUTPUT_WIDTH:-1920}"
OUTPUT_HEIGHT="${OUTPUT_HEIGHT:-1080}"
FPS="${FPS:-5}"
FRAMES="${FRAMES:-50}"
OUTPUT="${1:-input1080.yuv}"
ffmpeg -hide_banner -loglevel error -y \
  -f v4l2 -input_format yuyv422 \
  -video_size "${CAPTURE_WIDTH}x${CAPTURE_HEIGHT}" -framerate "$FPS" \
  -i "$CAMERA" -vf "scale=${OUTPUT_WIDTH}:${OUTPUT_HEIGHT}" \
  -frames:v "$FRAMES" -pix_fmt yuv420p -f rawvideo "$OUTPUT"
bytes=$(stat -c%s "$OUTPUT")
expected=$((OUTPUT_WIDTH * OUTPUT_HEIGHT * 3 / 2 * FRAMES))
[[ "$bytes" -eq "$expected" ]] || { echo "Unexpected output size: $bytes (expected $expected)" >&2; exit 1; }
echo "Captured $FRAMES frames to $OUTPUT ($bytes bytes)"
