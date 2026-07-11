#!/usr/bin/env bash
# build_apple_music_downloader.sh — 从 Get Oudio 专用 fork 构建并同步内嵌 Apple Music downloader。
# 用法: ./script/build_apple_music_downloader.sh
# 可选: APPLE_MUSIC_DOWNLOADER_SOURCE=/path/to/apple-music-downloader ./script/build_apple_music_downloader.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_SOURCE_DIR="$(cd "$ROOT_DIR/.." && pwd)/apple-music-downloader-get-oudio"
SOURCE_DIR="${APPLE_MUSIC_DOWNLOADER_SOURCE:-$DEFAULT_SOURCE_DIR}"
BUILD_DIR="$ROOT_DIR/build/apple-music-downloader"
GO_BUILD_CACHE="$BUILD_DIR/go-build-cache"
GO_MOD_CACHE="$BUILD_DIR/go-mod-cache"
DEST_DIR="$ROOT_DIR/GetOudio/Resources/ThirdParty/apple-music-downloader"
DEST_BINARY="$DEST_DIR/apple-music-downloader"
OUTPUT_BINARY="$BUILD_DIR/apple-music-downloader"

if [[ ! -d "$SOURCE_DIR/.git" ]]; then
    cat >&2 <<EOF
未找到 apple-music-downloader 源码仓库:
  $SOURCE_DIR

请先克隆 Get Oudio 专用 fork:
  git clone https://github.com/memomoonnnn/apple-music-downloader.git "$SOURCE_DIR"
EOF
    exit 1
fi

if ! command -v go >/dev/null 2>&1; then
    echo "未找到 go，请先安装 Go 工具链。" >&2
    exit 1
fi

mkdir -p "$BUILD_DIR" "$GO_BUILD_CACHE" "$GO_MOD_CACHE" "$DEST_DIR"

source_commit="$(git -C "$SOURCE_DIR" rev-parse --short=12 HEAD)"
source_branch="$(git -C "$SOURCE_DIR" branch --show-current || true)"
source_status="$(git -C "$SOURCE_DIR" status --short)"

echo "=== 构建 Get Oudio Apple Music downloader ==="
echo "源码目录: $SOURCE_DIR"
echo "源码版本: ${source_branch:-detached}@${source_commit}"
if [[ -n "$source_status" ]]; then
    echo "源码状态: 有未提交改动，将按当前工作树构建"
fi
echo "输出文件: $DEST_BINARY"
echo ""

(
    cd "$SOURCE_DIR"
    env \
        CGO_ENABLED=0 \
        GOOS=darwin \
        GOARCH=arm64 \
        GOCACHE="$GO_BUILD_CACHE" \
        GOMODCACHE="$GO_MOD_CACHE" \
        go build -trimpath -ldflags="-s -w" -o "$OUTPUT_BINARY" main.go
)

cp "$OUTPUT_BINARY" "$DEST_BINARY"
chmod +x "$DEST_BINARY"

echo ""
echo "=== 构建结果 ==="
ls -lh "$DEST_BINARY"
file "$DEST_BINARY"
echo ""
go version -m "$DEST_BINARY" | sed -n '1,40p'
echo ""
otool -L "$DEST_BINARY" || true
