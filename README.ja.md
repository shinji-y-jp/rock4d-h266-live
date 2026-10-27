# ROCK 4D H.266/VVC 実験 — 実測済みオフラインエンコードと試験的ライブ構成

[English](README.md)

Radxa ROCK 4D（RK3576）、Debian 12 ARM64、Fraunhofer **VVenC 1.15.0-dev**（GCC 12.2、NEON）、**VVdeC 3.3.0-dev** を使用。**実測に成功した保存済みYUVによる性能測定**と、**未検証のライブ実験スクリプト**を明確に分けています。DVB-S2送信成功を示すものではありません。

## 1. 依存パッケージとコーデックのビルド

```bash
sudo apt update
sudo apt install -y git build-essential cmake pkg-config ffmpeg python3 v4l-utils
mkdir -p ~/src
cd ~/src
git clone https://github.com/fraunhoferhhi/vvenc.git
cd vvenc
./make install-release-static
ls -l ~/src/vvenc/bin/release-static/vvencapp
cd ~/src
git clone https://github.com/fraunhoferhhi/vvdec.git
cd vvdec
# 先に以下のFIFOパッチ適用手順を実行
# ./make install-release-static
ls -l ~/src/vvdec/bin/release-static/vvdecapp
```

これは従来の実験で使用した手順です。上流の更新でビルド補助コマンドや出力先が変わる場合があります。測定時のVVenCは **1.15.0-dev** ですがGitコミット番号は未記録です。**VVdeC用パッチは同梱しておらず、適用済みとも主張していません。** 必要なパッチの有無は使用環境で別途確認してください。

## VVdeCのFIFO対応パッチ（必ずビルド前に適用）

`apply_vvdec_fifo_patch.py` は、実験で提示された **Annex B前方読み取り関数をそのまま**組み込み、`source/App/vvdecapp/vvdecHelper.h` を変更します。元ファイルは `.bak` に保存します。これは公式パッチではなく**実験版**です。VVdeC 3.3.0-dev の正確なコミットは記録されておらず、最新版での適用は保証されません。パッチ後のビルドと基本的なFIFO復号の報告はありますが、長時間の低遅延受像や再接続は未検証です。

```bash
sudo apt update
sudo apt install -y git cmake build-essential python3
mkdir -p ~/src
cd ~/src
git clone https://github.com/fraunhoferhhi/vvdec.git
cd vvdec
# 本リポジトリのパッチスクリプトをコピー（配置に応じて変更）
cp ~/rock4d-h266-live/apply_vvdec_fifo_patch.py .
python3 apply_vvdec_fifo_patch.py
./make install-release-static
ls -l ~/src/vvdec/bin/release-static/vvdecapp
```

既にVVdeCをクローン済みなら `git clone` は不要です。パッチがソースの不一致で停止した場合、無理に置換せずバージョンを確認してください。復元は `cp source/App/vvdecapp/vvdecHelper.h.bak source/App/vvdecapp/vvdecHelper.h` です。

**注意:** `live.sh` は実験用です。1920×1080のカメラ入力設定や `~/y4m_pacer.py` の配置には調整が必要です。ライブ連続受像・DVB-S2送信の成功は主張していません。

## 2. GitHubからクローン

リポジトリを公開した後に実行：

```bash
cd ~
git clone https://github.com/shinji-y-jp/rock4d-h266-live.git
cd rock4d-h266-live
chmod +x capture_yuv.sh benchmark.sh decode_file.sh live.sh
```

未公開なら、まずZIP内のファイルを `rock4d-h266-live` リポジトリにアップロードするか、ZIPを展開して直接使用してください。

## 3. カメラ対応モードの確認

```bash
v4l2-ctl -d /dev/video0 --list-formats-ext
```

成功した1080pエンコード試験は、カメラの **800×448 / YUYV422 / 5fps** をFFmpegで **1920×1080へ拡大**したYUV420pファイルを使用しました。**ネイティブ1080p撮影ではありません。**

## 4. カメラ入力とエンコードを分離して測定

```bash
./capture_yuv.sh input1080.yuv
./benchmark.sh input1080.yuv 1920 1080 8 50 test.266
```

実験時に使用したコマンド全文：

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

既存のYUVファイルがある場合、FFmpegは上書き確認を表示します。`capture_yuv.sh` は上書き指定です。**raw YUVには解像度ヘッダーがありません。** `-s` を変更したら入力ファイルも正しい解像度で再生成してください。1920×1080×50フレームのYUV420pファイルは **155,520,000バイト**です。

640×480で測定：

```bash
CAPTURE_WIDTH=640 CAPTURE_HEIGHT=480 OUTPUT_WIDTH=640 OUTPUT_HEIGHT=480 ./capture_yuv.sh input640.yuv
./benchmark.sh input640.yuv 640 480 6 50 test640.266
```

640×480入力を320×240へ縮小して測定：

```bash
CAPTURE_WIDTH=640 CAPTURE_HEIGHT=480 OUTPUT_WIDTH=320 OUTPUT_HEIGHT=240 ./capture_yuv.sh input320.yuv
./benchmark.sh input320.yuv 320 240 6 50 test320.266
```

## 5. H.266デコード

```bash
./decode_file.sh test.266 test.y4m
ffplay test.y4m
```

内部で `vvdecapp -b test.266 -o test.y4m --y4m` を実行します。実験環境のFFmpeg 5.1.9のffplayでは `.266` の直接デコードができませんでした。別の試験ではVLCで `.266` を開けています。VVdeC標準出力を直接ffplayへ接続する方法は、過去に `Header too large` エラーが出ており、**動作確認済みとはしていません**。

## 6. 実測結果（保存済みYUV、50フレーム、5Hz、QP45）

| エンコーダー入力 | スレッド | 処理時間 | エンコード速度 | 平均VVCビットレート |
|---|---:|---:|---:|---:|
| 320×240 | 6 | 0.695秒 | 71.942fps | 9.344kbps |
| 640×480 | 6 | 2.002秒 | 24.975fps | 21.245kbps |
| 1920×1080（640×480を拡大） | 6 | 10.528秒 | 4.749fps | 58.150kbps |
| 1920×1080（800×448を拡大） | 6 | 10.979秒 | 4.554fps | 58.705kbps |
| **1920×1080（同じ800×448映像）** | **8** | **9.737秒** | **5.135fps** | **58.705kbps** |

最終結果はIフレーム10枚、Bフレーム40枚、`--preset faster --qpa off --mtprofile 0 -b 0 -q 45 -p 1 -rt idr -ip 5`。**58.7kbpsはこの短い映像の実測平均であり、上限保証ではありません。** 5.135fpsは**保存済みファイルの平均エンコード処理速度**で、カメラを含む連続リアルタイム処理、遅延、受像、DVB-S2送信を証明するものではありません。

以前のカメラ直結試験で約4.78fpsだったのは、カメラ入力が5fpsに設定されていたためです。入力とエンコードを分離して初めてエンコーダー単体の速度を測定できました。

## 7. ライブ実験（全段動作は未検証）

元ZIPの `live.sh` と `y4m_pacer.py` は**変更せず収録**しました。`live.sh` の初期値は **1920×1080 YUYV422カメラ入力・5fps・QP42・8スレッド・1500フレーム・デコーダー起動待ち2秒**。今回の成功したQP45／800×448カメラ入力の試験条件とは**異なります**。まずカメラの対応モードを確認してください。

`live.sh` は `~/y4m_pacer.py` を参照します。

```bash
cp -i y4m_pacer.py ~/
./live.sh
```

1080p YUYVモードがカメラにない可能性、FIFOの待ち、VVdeCの標準出力にY4M以外が混入する可能性、Ctrl+C後の子プロセス残留などに注意。`DELAY=2` は起動待ちであって映像遅延の実測値ではありません。**ライブ送受像の成功を保証しません。**

## 8. DVB-S2と著作権

約58.7kbpsのVVCビットストリームは狭帯域DATVに有望ですが、必要なシンボルレートはMODCOD・フレーミング・TS多重化などのオーバーヘッドで変化します。RF/DVB-S2試験は含みません。VVenC/VVdeCの実行ファイルやパッチは同梱していません。上流のライセンスに従ってください。

実験：**山崎慎慈（JE1BTA）**。
