#!/usr/bin/env bash
set -euo pipefail
DEC="${DEC:-$HOME/src/vvdec/bin/release-static/vvdecapp}"
INPUT="${1:-test.266}"
OUTPUT="${2:-test.y4m}"
[[ -x "$DEC" ]] || { echo "Decoder not executable: $DEC" >&2; exit 1; }
"$DEC" -b "$INPUT" -o "$OUTPUT" --y4m
printf 'Decoded to %s. Try: ffplay %q\n' "$OUTPUT" "$OUTPUT"
