#!/bin/bash

# ROCK 4D H.266 FIFO Delay Test
# C920 -> FFmpeg -> VVenC -> FIFO -> VVdeC -> FFplay

set -uo pipefail

ENC="$HOME/src/vvenc/bin/release-static/vvencapp"
DEC="$HOME/src/vvdec/bin/release-static/vvdecapp"

CAMERA="/dev/video0"
FIFO="/tmp/camera_live.fifo"

WIDTH=1920
HEIGHT=1080
FPS=5
FRAMES=1500

DELAY=2

rm -f "$FIFO"
mkfifo "$FIFO"

cleanup() {
    trap - EXIT INT TERM

    if [[ -n "${ENC_PID:-}" ]]; then
        kill "$ENC_PID" 2>/dev/null || true
    fi

    rm -f "$FIFO"
}

trap cleanup EXIT
trap 'exit 130' INT TERM

echo "=== H.266 FIFO DELAY TEST ==="

echo "Starting encoder..."

(
    ffmpeg -hide_banner -loglevel warning \
        -f v4l2 \
        -input_format yuyv422 \
        -video_size "${WIDTH}x${HEIGHT}" \
        -framerate "$FPS" \
        -i "$CAMERA" \
        -frames:v "$FRAMES" \
        -an \
        -pix_fmt yuv420p \
        -f rawvideo pipe:1 \
    | "$ENC" \
        -i - \
        -s "${WIDTH}x${HEIGHT}" \
        -c yuv420 \
        -r "$FPS" \
        -f "$FRAMES" \
        --preset faster \
        --qpa off \
        -t 8 \
        --mtprofile 0 \
        -b 0 \
        -q 42 \
        -p 1 \
        -rt idr \
        -ip 5 \
        -o "$FIFO"
) &

ENC_PID=$!

echo "Waiting ${DELAY} seconds..."
sleep "$DELAY"

echo "Starting decoder..."

"$DEC" \
    -b "$FIFO" \
    -o - \
    --y4m \
    -t 8 \
    -v 0 \
| python3 -u ~/y4m_pacer.py \
| ffplay \
    -hide_banner \
    -loglevel warning \
    -sync video \
    -f yuv4mpegpipe \
    -i pipe:0

wait "$ENC_PID"

echo "=== FINISHED ==="
