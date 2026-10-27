#!/usr/bin/env bash
# Reproducible offline VVenC test; webcam capture is intentionally separate.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENC="${ENC:-$HOME/src/vvenc/bin/release-static/vvencapp}"
INPUT="${1:-input1080.yuv}"
WIDTH="${2:-1920}"
HEIGHT="${3:-1080}"
THREADS="${4:-8}"
FRAMES="${5:-50}"
OUT="${6:-test.266}"
FPS="${FPS:-5}"
QP="${QP:-45}"
[[ -x "$ENC" ]] || { echo "Encoder not executable: $ENC" >&2; exit 1; }
[[ -f "$INPUT" ]] || { echo "Missing input: $INPUT" >&2; exit 1; }
expected=$((WIDTH * HEIGHT * 3 / 2 * FRAMES))
actual=$(stat -c%s "$INPUT")
if ((actual < expected)); then echo "Input too short: need $expected bytes for $FRAMES frames at ${WIDTH}x${HEIGHT}, found $actual" >&2; exit 1; fi
if ((actual % (WIDTH * HEIGHT * 3 / 2) != 0)); then echo "Warning: file size not a whole number of frames at requested dimensions" >&2; fi
"$ENC" -i "$INPUT" -s "${WIDTH}x${HEIGHT}" -c yuv420 -r "$FPS" -f "$FRAMES" \
  --preset faster --qpa off -t "$THREADS" --mtprofile 0 \
  -b 0 -q "$QP" -p 1 -rt idr -ip 5 -o "$OUT"
