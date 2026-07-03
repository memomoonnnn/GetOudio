#!/usr/bin/env bash
# build_minimal_ffmpeg.sh — 编译精简版 ffmpeg（仅保留音频转换所需的功能）
# 用法: ./script/build_minimal_ffmpeg.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/ffmpeg-build"
FFMPEG_VERSION="8.1"
FFMPEG_TARBALL="ffmpeg-${FFMPEG_VERSION}.tar.xz"
FFMPEG_URL="https://ffmpeg.org/releases/${FFMPEG_TARBALL}"
THIRD_PARTY="$ROOT_DIR/GetOudio/Resources/ThirdParty/ffmpeg"
MAKEFLAGS="${MAKEFLAGS:-$(( $(sysctl -n hw.ncpu 2>/dev/null || echo 4) + 1 ))}"

echo "=== 编译精简版 ffmpeg ${FFMPEG_VERSION} ==="
echo "构建目录: $BUILD_DIR"
echo "输出目录: $THIRD_PARTY"
echo "并行任务: $MAKEFLAGS"
echo ""

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# ---------- 下载源码 ----------
if [[ ! -f "$FFMPEG_TARBALL" ]]; then
    echo "--- 下载 ffmpeg 源码 ---"
    curl -#L -o "$FFMPEG_TARBALL" "$FFMPEG_URL"
fi

if [[ ! -d "ffmpeg-${FFMPEG_VERSION}" ]]; then
    echo "--- 解压 ---"
    tar xf "$FFMPEG_TARBALL"
fi

cd "ffmpeg-${FFMPEG_VERSION}"

# ---------- 配置 ----------
echo "--- 配置编译选项 ---"

# 外部音频编码库路径
LAME_PREFIX="$(brew --prefix lame 2>/dev/null || echo '/opt/homebrew/opt/lame')"
OPUS_PREFIX="$(brew --prefix opus 2>/dev/null || echo '/opt/homebrew/opt/opus')"
VORBIS_PREFIX="$(brew --prefix libvorbis 2>/dev/null || echo '/opt/homebrew/opt/libvorbis')"
OGG_PREFIX="$(brew --prefix libogg 2>/dev/null || echo '/opt/homebrew/opt/libogg')"
PKGCONF_PREFIX="$(brew --prefix pkgconf 2>/dev/null || brew --prefix pkg-config 2>/dev/null || echo '/opt/homebrew/opt/pkgconf')"

# 确保 configure 能找到外部编码库，并尽量把第三方编码库静态链接进 ffmpeg。
EXTERNAL_CFLAGS="-I${LAME_PREFIX}/include -I${OPUS_PREFIX}/include -I${VORBIS_PREFIX}/include -I${OGG_PREFIX}/include"
EXTERNAL_LDFLAGS="-L${LAME_PREFIX}/lib -Wl,-force_load,${LAME_PREFIX}/lib/libmp3lame.a -Wl,-dead_strip_dylibs"
STATIC_PKG_CONFIG_DIR="$BUILD_DIR/pkgconfig-static"
mkdir -p "$STATIC_PKG_CONFIG_DIR"
cat > "$STATIC_PKG_CONFIG_DIR/opus.pc" <<EOF
Name: opus
Description: Opus codec library
Version: 1
Cflags: -I${OPUS_PREFIX}/include/opus
Libs: ${OPUS_PREFIX}/lib/libopus.a -lm
EOF
cat > "$STATIC_PKG_CONFIG_DIR/ogg.pc" <<EOF
Name: ogg
Description: Ogg bitstream library
Version: 1
Cflags: -I${OGG_PREFIX}/include
Libs: ${OGG_PREFIX}/lib/libogg.a
EOF
cat > "$STATIC_PKG_CONFIG_DIR/vorbis.pc" <<EOF
Name: vorbis
Description: Vorbis codec library
Version: 1
Requires: ogg
Cflags: -I${VORBIS_PREFIX}/include
Libs: ${VORBIS_PREFIX}/lib/libvorbis.a -lm
EOF
cat > "$STATIC_PKG_CONFIG_DIR/vorbisenc.pc" <<EOF
Name: vorbisenc
Description: Vorbis encoder library
Version: 1
Requires: vorbis
Cflags: -I${VORBIS_PREFIX}/include
Libs: ${VORBIS_PREFIX}/lib/libvorbisenc.a
EOF
export PKG_CONFIG="${PKGCONF_PREFIX}/bin/pkg-config"
export PKG_CONFIG_PATH="$STATIC_PKG_CONFIG_DIR:${PKG_CONFIG_PATH:-}"

./configure \
    --prefix="$BUILD_DIR/install" \
    --disable-everything \
    --pkg-config-flags="--static" \
    --extra-cflags="$EXTERNAL_CFLAGS" \
    --extra-ldflags="$EXTERNAL_LDFLAGS" \
    \
    `# === 核心组件 ===` \
    --enable-avcodec \
    --enable-avformat \
    --enable-avutil \
    --enable-swresample \
    --enable-avfilter \
    --enable-ffmpeg \
    \
    `# === 音频解码器（覆盖常见输入格式）===` \
    --enable-decoder=aac,aac_at,aac_fixed,aac_latm \
    --enable-decoder=mp3,mp3adu,mp3float,mp3on4,mp3on4float \
    --enable-decoder=flac \
    --enable-decoder=alac,alac_at \
    --enable-decoder=pcm_s16le,pcm_s16be,pcm_s24le,pcm_s24be,pcm_s32le,pcm_s32be \
    --enable-decoder=pcm_f32le,pcm_f32be,pcm_f64le,pcm_f64be \
    --enable-decoder=vorbis \
    --enable-decoder=opus \
    --enable-decoder=ac3,ac3_fixed,eac3 \
    --enable-decoder=wmav1,wmav2,wmapro,wmalossless \
    --enable-decoder=wavpack \
    --enable-decoder=ape \
    --enable-decoder=tta \
    --enable-decoder=amrnb,amrwb \
    --enable-decoder=dca,dts \
    --enable-decoder=truehd,mlp \
    --enable-decoder=tak \
    --enable-decoder=ra_144,ra_288,ralf,cook,atrac1,atrac3,atrac3p,atrac9 \
    --enable-decoder=adpcm_ima_wav,adpcm_ms,adpcm_g722,adpcm_g726,adpcm_g726le \
    \
    `# === 音频编码器 ===` \
    --enable-encoder=aac,aac_at \
    --enable-encoder=alac,alac_at \
    --enable-encoder=flac \
    --enable-encoder=pcm_s16le,pcm_s16be,pcm_s24le,pcm_s24be,pcm_s32le,pcm_s32be \
    --enable-encoder=pcm_f32le,pcm_f32be \
    --enable-libmp3lame --enable-encoder=libmp3lame \
    --enable-libvorbis --enable-encoder=libvorbis \
    --enable-libopus --enable-encoder=libopus \
    \
    `# === 解复用器（读取输入文件）===` \
    --enable-demuxer=mov,m4v,mp3,wav,flac,ogg,aac,ac3,eac3 \
    --enable-demuxer=matroska,webm_dash_manifest \
    --enable-demuxer=avi,asf,wmv \
    --enable-demuxer=pcm_s16le,pcm_s24le,pcm_s32le,pcm_f32le \
    --enable-demuxer=ape,tta,wv \
    --enable-demuxer=dts,dtshd,truehd \
    --enable-demuxer=tak,shorten \
    --enable-demuxer=rm,ra \
    --enable-demuxer=amr \
    --enable-demuxer=au,caf,ast \
    --enable-demuxer=aiff \
    --enable-demuxer=loas,latm \
    \
    `# === 复用器（写入输出文件）===` \
    --enable-muxer=mp4,ipod \
    --enable-muxer=mp3 \
    --enable-muxer=wav \
    --enable-muxer=flac \
    --enable-muxer=ogg \
    --enable-muxer=adts \
    --enable-muxer=caf \
    --enable-muxer=aiff \
    --enable-muxer=au \
    --enable-muxer=pcm_s16le,pcm_s24le,pcm_s32le,pcm_f32le \
    \
    `# === 解析器 ===` \
    --enable-parser=aac,aac_latm,ac3,flac,mpegaudio,opus,vorbis \
    --enable-parser=dca,mlp \
    --enable-parser=amrnb,amrwb \
    --enable-parser=tak \
    --enable-parser=cook \
    \
    `# === 协议 ===` \
    --enable-protocol=file,pipe \
    \
    `# === 比特流过滤器 ===` \
    --enable-bsf=aac_adtstoasc,mp3_header_decompress,extract_extradata \
    --enable-bsf=dca_core \
    --enable-bsf=mov2textsub,text2movsub,noise \
    \
    `# === 滤波器 ===` \
    --enable-filter=anull,anullsink,aformat,aresample \
    \
    `# === 编译选项 ===` \
    --enable-static \
    --disable-shared \
    --enable-gpl \
    --enable-small \
    --disable-doc \
    --disable-ffplay \
    --disable-ffprobe \
    --disable-network \
    --disable-autodetect \
    --disable-avdevice \
    --disable-swscale \
    \
    `# === 平台优化 ===` \
    --enable-pthreads \
    --enable-videotoolbox \
    --enable-audiotoolbox \
    --enable-neon \
    --cc=clang

# ---------- 编译 ----------
echo ""
echo "--- 编译（使用 $MAKEFLAGS 个并行任务）---"
make -j"$MAKEFLAGS" 2>&1 | grep -E "^(CC|LD|AR|GEN|error|warning:.*error)" || true

echo ""
echo "--- 安装 ---"
make install 2>&1 | tail -5

# ---------- 复制到 ThirdParty ----------
echo ""
echo "--- 部署到 ThirdParty ---"
rm -rf "$THIRD_PARTY"
mkdir -p "$THIRD_PARTY"
cp "$BUILD_DIR/install/bin/ffmpeg" "$THIRD_PARTY/ffmpeg"
chmod +x "$THIRD_PARTY/ffmpeg"

echo ""
echo "=== 完成 ==="
echo "精简版 ffmpeg 已安装到: $THIRD_PARTY/ffmpeg"
"$THIRD_PARTY/ffmpeg" -version 2>&1 | head -5
echo ""
echo "二进制大小:"
ls -lh "$THIRD_PARTY/ffmpeg" | awk '{print $5}'
