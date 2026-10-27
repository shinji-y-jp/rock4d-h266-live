# ROCK 4D H.266/VVC experiments — measured offline encoding and experimental live pipeline

[日本語](README.ja.md)

Radxa ROCK 4D (RK3576), Debian 12 ARM64, Fraunhofer **VVenC 1.15.0-dev** (GCC 12.2, NEON), **VVdeC 3.3.0-dev**. This repository includes the **verified offline benchmarking workflow** and a **separate, experimental live pipeline**. It is **not** a demonstrated H.266 DVB-S2 transmitter.

## 1. Install prerequisites and build codecs

```bash
sudo apt update
sudo apt install -y git build-essential cmake pkg-config ffmpeg python3 v4l-utils
mkdir -p ~/src
cd ~/src
git clone https://github.com/fraunhoferhhi/vvenc.git
cd vvenc
./make release
ls -l ~/src/vvenc/bin/release-static/vvencapp
cd ~/src
git clone https://github.com/fraunhoferhhi/vvdec.git
cd vvdec
# IMPORTANT: apply FIFO patch first (see section below).
# ./make release
ls -l ~/src/vvdec/bin/release-static/vvdecapp
```

These are the build commands used in the earlier experiment; upstream revisions may change the helper or output path. The benchmark was run with VVenC **1.15.0-dev**; the exact Git commit was not recorded, so builds from current upstream are not guaranteed to match. Check the upstream repositories if a build fails. The experimental VVdeC FIFO patch is included as `apply_vvdec_fifo_patch.py`. Apply it **before building VVdeC**; see the instructions below.

## VVdeC FIFO patch — apply BEFORE compiling

This repository includes the **exact forward-only Annex B reader function supplied in the ROCK 4D experiment**, wrapped in a guarded patch script. It changes `source/App/vvdecapp/vvdecHelper.h` and creates `.bak`. It is **experimental, not an official upstream fix**. The source layout may differ across VVdeC revisions; the exact Git commit of the tested 3.3.0-dev tree was not recorded. A successful build and basic FIFO decode were reported; continuous low-latency playback and reconnection are not proven.

```bash
cd ~/src/vvdec

cp source/App/vvdecapp/vvdecHelper.h \
   source/App/vvdecapp/vvdecHelper.h.bak
```




```bash
cd ~/src/vvdec

python3 - <<'PY'
from pathlib import Path

p = Path("source/App/vvdecapp/vvdecHelper.h")
s = p.read_text()

start = s.index("static int readBitstreamFromFile(")
end = s.index("\n  /**", start)

new = r'''static int readBitstreamFromFile(
    std::ifstream *f,
    vvdecAccessUnit* pcAccessUnit,
    bool bLoop )
{
  // Forward-only Annex B reader.
  // Supports regular files and non-seekable FIFOs.
  // State is retained between calls for the same stream.

  static std::ifstream* lastStream = nullptr;
  static std::vector<unsigned char> pending;

  if( lastStream != f )
  {
    pending.clear();
    lastStream = f;
  }

  std::vector<unsigned char> nal;
  nal.swap( pending );

  // Locate the first Annex B start code.
  // 00 00 01 or 00 00 00 01
  if( nal.empty() )
  {
    unsigned char b;
    int zeros = 0;

    while( f->read( reinterpret_cast<char*>(&b), 1 ) )
    {
      if( b == 0 )
      {
        zeros++;
      }
      else if( b == 1 && zeros >= 2 )
      {
        nal.assign( zeros >= 3 ? 4 : 3, 0 );
        nal.back() = 1;
        break;
      }
      else
      {
        zeros = 0;
      }
    }

    if( nal.empty() )
      return -1;
  }

  unsigned char b;
  int zeros = 0;

  while( f->read( reinterpret_cast<char*>(&b), 1 ) )
  {
    nal.push_back( b );

    if( b == 0 )
    {
      zeros++;
      continue;
    }

    if( b == 1 && zeros >= 2 )
    {
      const size_t prefix = zeros >= 3 ? 4 : 3;

      // Preserve the next NAL start code.
      pending.assign( nal.end() - prefix, nal.end() );
      nal.resize( nal.size() - prefix );
      break;
    }

    zeros = 0;
  }

  if( nal.empty() )
    return -1;

  if( nal.size() > pcAccessUnit->payloadSize )
  {
    unsigned char* newbuf =
      static_cast<unsigned char*>( malloc( nal.size() ) );

    if( !newbuf )
      return -1;

    free( pcAccessUnit->payload );
    pcAccessUnit->payload = newbuf;
    pcAccessUnit->payloadSize = nal.size();
  }

  std::copy( nal.begin(), nal.end(), pcAccessUnit->payload );

  pcAccessUnit->payloadUsedSize = nal.size();

  return static_cast<int>( nal.size() );
}
```

If you already cloned VVdeC, omit `git clone`. If the patch refuses because the file differs, inspect the version rather than forcing a replacement. For a fresh rebuild of a previously built tree, clean/reconfigure according to upstream build instructions. Restore the original with `cp source/App/vvdecapp/vvdecHelper.h.bak source/App/vvdecapp/vvdecHelper.h`.

**Important:** the live script is still an *experimental* pipeline. Its 1920×1080 camera capture mode and `~/y4m_pacer.py` path may need local adjustment; no verified uninterrupted live reception or DVB-S2 transmission is claimed.

## 2. Clone this repository

After publishing to your GitHub account:

```bash
cd ~
git clone https://github.com/shinji-y-jp/rock4d-h266-live.git
cd rock4d-h266-live
chmod +x *.sh
chmod +x *.py
```

If that repository URL has not yet been created, upload this ZIP's folder contents to a new repository named `rock4d-h266-live`, or extract the ZIP and run locally without cloning.

## 3. Inspect webcam modes

```bash
v4l2-ctl -d /dev/video0 --list-formats-ext
```

The successful 1080p *encoding* test captured **800×448 YUYV422 at 5fps** and **upscaled** to 1920×1080 YUV420p. It was **not native 1080p camera capture**. This scaling can change image detail and compression complexity.

## 4. Capture 50 YUV frames, then benchmark separately

```bash
./capture_yuv.sh input1080.yuv
./benchmark.sh input1080.yuv 1920 1080 8 50 test.266
```

Equivalent exact commands used in the successful experiment:

```bash
ffmpeg -hide_banner -loglevel error \
  -f v4l2 -input_format yuyv422 -video_size 800x448 -framerate 5 \
  -i /dev/video0 -vf scale=1920:1080 -frames:v 50 \
  -pix_fmt yuv420p -f rawvideo input1080.yuv

~/src/vvenc/bin/release-static/vvencapp \
  -i input1080.yuv -s 1920x1080 -c yuv420 -r 5 -f 50 \
  --preset faster --qpa off -t 8 --mtprofile 0 \
  -b 0 -q 45 -p 1 -rt idr -ip 5 -o test.266
```

For an existing file, FFmpeg may ask whether to overwrite; `capture_yuv.sh` explicitly overwrites. **Do not change `-s` without regenerating the raw input at the matching dimensions.** YUV420p has no embedded size header; mismatched dimensions silently corrupt frame boundaries. For 1920×1080 × 50 frames the expected input size is **155,520,000 bytes**.

To reproduce the earlier 640×480 camera capture and test:

```bash
CAPTURE_WIDTH=640 CAPTURE_HEIGHT=480 OUTPUT_WIDTH=640 OUTPUT_HEIGHT=480 ./capture_yuv.sh input640.yuv
./benchmark.sh input640.yuv 640 480 6 50 test640.266
```

To capture 320×240 *scaled* from 640×480:

```bash
CAPTURE_WIDTH=640 CAPTURE_HEIGHT=480 OUTPUT_WIDTH=320 OUTPUT_HEIGHT=240 ./capture_yuv.sh input320.yuv
./benchmark.sh input320.yuv 320 240 6 50 test320.266
```

## 5. Decode the output file

```bash
./decode_file.sh test.266 test.y4m
ffplay test.y4m
```

This invokes `vvdecapp -b test.266 -o test.y4m --y4m`. `ffplay` on this system (FFmpeg 5.1.9) did **not** directly decode `.266`; use VVdeC first. VLC was able to open the `.266` file in a separate earlier test. The live VVdeC → stdout → ffplay Y4M path has **not** been validated as working; a prior attempt produced `Header too large`.

## 6. Measured results (offline input, 50 frames, 5Hz, QP45)

| Input to encoder | Threads | Time | Encoder throughput | Average VVC bitrate |
|---|---:|---:|---:|---:|
| 320×240 | 6 | 0.695 s | 71.942 fps | 9.344 kbps |
| 640×480 | 6 | 2.002 s | 24.975 fps | 21.245 kbps |
| 1920×1080 (640×480 webcam upscaled) | 6 | 10.528 s | 4.749 fps | 58.150 kbps |
| 1920×1080 (800×448 webcam upscaled) | 6 | 10.979 s | 4.554 fps | 58.705 kbps |
| **1920×1080 (same 800×448 source)** | **8** | **9.737 s** | **5.135 fps** | **58.705 kbps** |

The final 8-thread result used 10 I frames and 40 B frames, `--preset faster --qpa off --mtprofile 0 -b 0 -q 45 -p 1 -rt idr -ip 5`. Average bitrate **58.7 kbps** is an observed result for this short clip, **not** a rate cap or a guaranteed value for motion-rich video. The 5.135 fps number is **offline average encoder throughput**, not proof of sustained real-time capture, bounded latency, decoding, or DVB-S2 transmission.

Earlier direct webcam-to-encoder tests measured ~4.78 fps at 320×240 because the webcam was set to 5 fps; the separate-file test exposed the actual offline encoder throughput.

## 7. Experimental live pipeline (not verified end-to-end)

The original `live.sh` and `y4m_pacer.py` are retained **unchanged** from the supplied ZIP for historical reference. `live.sh` defaults to **1920×1080 YUYV422 capture at 5fps**, **QP42**, 8 encoder threads, 1500 frames, and a 2-second decoder-start wait. These are **not** the settings used for the validated QP45 / 800×448 camera benchmark. Check camera support first. `live.sh` expects `~/y4m_pacer.py`:

```bash
cp -i y4m_pacer.py ~/
./live.sh
```

Potential issues: direct 1080p YUYV capture may not be available; FIFO operations may block; VVdeC stdout may not produce a clean Y4M stream; child processes may remain after Ctrl+C. The script's `DELAY=2` is a startup delay, not measured video latency. **No claim is made that the live chain works end-to-end.**

## 8. DVB-S2 scope and attribution

A ~58.7 kbps VVC elementary stream is promising for narrowband DATV, but actual DVB-S2 symbol rate depends on MODCOD, framing, multiplexing, and overhead. No RF/DVB-S2 test is included. No VVenC/VVdeC binaries or patch files are included; upstream licenses apply. Experiment: **Shinji Yamazaki (JE1BTA)**.
