#!/usr/bin/env bash
# bundle_deps.sh — 将仍需随 App 分发的轻量组件放入 ThirdParty。
# Apple Music 的 Colima/Lima/Docker/GPAC 运行时由 AM Runtime Agent 启用后安装到用户 Application Support。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THIRD_PARTY="$ROOT_DIR/GetOudio/Resources/ThirdParty"

echo "=== Get Oudio 内嵌组件整理 ==="
echo "目标目录: $THIRD_PARTY"
echo ""

find_binary() {
    local name="$1"
    if command -v brew &>/dev/null; then
        local brew_prefix
        brew_prefix="$(brew --prefix 2>/dev/null || echo '')"
        if [[ -n "$brew_prefix" && -x "$brew_prefix/bin/$name" ]]; then
            echo "$brew_prefix/bin/$name"
            return 0
        fi
    fi

    local found
    found="$(command -v "$name" 2>/dev/null || echo '')"
    if [[ -n "$found" && -x "$found" ]]; then
        echo "$found"
        return 0
    fi
    return 1
}

copy_with_direct_dylibs() {
    local src="$1"
    local dest_dir="$2"
    local binary_name
    binary_name="$(basename "$src")"

    mkdir -p "$dest_dir"
    cp "$src" "$dest_dir/$binary_name"
    chmod +x "$dest_dir/$binary_name"
    echo "  ✓ 复制 $binary_name → $dest_dir/$binary_name"

    for lib in $(otool -L "$src" 2>/dev/null | grep -E '^\s+/opt/homebrew|^\s+/usr/local/(Cellar|opt)' | awk '{print $1}' || true); do
        local lib_name
        lib_name="$(basename "$lib")"
        if [[ ! -f "$dest_dir/$lib_name" ]]; then
            cp "$lib" "$dest_dir/$lib_name"
            chmod 644 "$dest_dir/$lib_name"
            echo "  ✓ 复制依赖库 $lib_name → $dest_dir/"
        fi
        install_name_tool -change "$lib" "@loader_path/$lib_name" "$dest_dir/$binary_name" 2>/dev/null || true
    done
}

echo "--- ffmpeg ---"
FFMPEG_DEST="$THIRD_PARTY/ffmpeg"
if [[ -x "$FFMPEG_DEST/ffmpeg" ]]; then
    echo "  ✓ 已存在，跳过"
else
    FFMPEG_SRC=$(find_binary ffmpeg) || true
    if [[ -n "${FFMPEG_SRC:-}" ]]; then
        copy_with_direct_dylibs "$FFMPEG_SRC" "$FFMPEG_DEST"
    else
        echo "  ⚠ 未找到 ffmpeg；推荐使用 script/build_minimal_ffmpeg.sh 生成精简版"
    fi
fi

echo "--- ncmdump ---"
if [[ -x "$THIRD_PARTY/ncmdump/bin/ncmdump" ]]; then
    echo "  ✓ 已存在，跳过"
else
    echo "  ⚠ 未找到 ncmdump，请手动放入 $THIRD_PARTY/ncmdump/bin/"
fi

echo "--- Apple-Music-Downloader ---"
if [[ -x "$THIRD_PARTY/apple-music-downloader/apple-music-downloader" ]]; then
    echo "  ✓ 已存在，跳过"
else
    echo "  ⚠ 未找到 apple-music-downloader，请手动放入 $THIRD_PARTY/apple-music-downloader/"
fi

echo ""
echo "=== 完成 ==="
echo "App Bundle 只应继续内嵌："
echo "  ThirdParty/ffmpeg/"
echo "  ThirdParty/ncmdump/"
echo "  ThirdParty/apple-music-downloader/"
echo ""
echo "Apple Music 运行时请使用 script/package_gpac_runtime.sh 准备 GPAC 包，其余依赖由 AM Runtime Agent 启用后下载到用户 Application Support。"
