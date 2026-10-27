#!/usr/bin/env python3

import sys
import time
import re

inp = sys.stdin.buffer
out = sys.stdout.buffer

header = inp.readline()

if not header.startswith(b"YUV4MPEG2 "):
    sys.exit("ERROR: Invalid Y4M header")

def field(prefix):
    for token in header.split():
        if token.startswith(prefix):
            return token[len(prefix):]
    raise ValueError("Missing Y4M field")

width = int(field(b"W"))
height = int(field(b"H"))

fps_text = field(b"F").decode()
num, den = map(int, fps_text.split(":"))
fps = num / den

chroma = field(b"C").decode()

if not chroma.startswith("420"):
    sys.exit("ERROR: Only YUV420 supported")

depth_match = re.search(r"p(\d+)", chroma)
depth = int(depth_match.group(1)) if depth_match else 8

bytes_per_sample = 2 if depth > 8 else 1
frame_size = width * height * 3 // 2 * bytes_per_sample

period = 1.0 / fps

print(
    f"Y4M PACER: {width}x{height} "
    f"{fps:.2f}fps {depth}bit",
    file=sys.stderr
)

out.write(header)
out.flush()

next_time = time.monotonic()
count = 0

while True:

    frame_header = inp.readline()

    if not frame_header:
        break

    if not frame_header.startswith(b"FRAME"):
        sys.exit("ERROR: Invalid frame header")

    frame = bytearray()

    while len(frame) < frame_size:
        chunk = inp.read(frame_size - len(frame))
        if not chunk:
            break
        frame.extend(chunk)

    if len(frame) != frame_size:
        break

    now = time.monotonic()

    if now < next_time:
        time.sleep(next_time - now)

    try:
        out.write(frame_header)
        out.write(frame)
        out.flush()
    except BrokenPipeError:
        break

    count += 1
    next_time += period

    # Avoid accumulating excessive delay.
    if next_time < time.monotonic() - period:
        next_time = time.monotonic()

print(f"PACER: {count} frames", file=sys.stderr)
