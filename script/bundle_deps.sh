#!/usr/bin/env bash
# bundle_deps.sh — 将 Homebrew 安装的运行时依赖提取并嵌入 App Bundle
# 用法: ./script/bundle_deps.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THIRD_PARTY="$ROOT_DIR/GetOudio/Resources/ThirdParty"

echo "=== Get Oudio 依赖嵌入工具 ==="
echo "目标目录: $THIRD_PARTY"
echo ""

# ---------- helper: 查找二进制 ----------
find_binary() {
    local name="$1"
    # 优先从 Homebrew 查找
    if command -v brew &>/dev/null; then
        local brew_prefix
        brew_prefix="$(brew --prefix 2>/dev/null || echo '')"
        if [[ -n "$brew_prefix" && -x "$brew_prefix/bin/$name" ]]; then
            echo "$brew_prefix/bin/$name"
            return 0
        fi
    fi
    # 回退到 PATH
    local found
    found="$(command -v "$name" 2>/dev/null || echo '')"
    if [[ -n "$found" && -x "$found" ]]; then
        echo "$found"
        return 0
    fi
    return 1
}

# ---------- 复制二进制及其直接依赖的 dylib ----------
copy_with_dylibs() {
    local src="$1"
    local dest_dir="$2"
    local binary_name
    binary_name="$(basename "$src")"

    mkdir -p "$dest_dir"
    cp "$src" "$dest_dir/$binary_name"
    chmod +x "$dest_dir/$binary_name"
    echo "  ✓ 复制 $binary_name → $dest_dir/$binary_name"

    # 复制 brew 相关的 dylib 依赖（非系统库）
    for lib in $(otool -L "$src" 2>/dev/null | grep -E '^\s+/opt/homebrew|^\s+/usr/local/(Cellar|opt)' | awk '{print $1}' || true); do
        local lib_name
        lib_name="$(basename "$lib")"
        if [[ ! -f "$dest_dir/$lib_name" ]]; then
            cp "$lib" "$dest_dir/$lib_name"
            chmod 644 "$dest_dir/$lib_name"
            echo "  ✓ 复制依赖库 $lib_name → $dest_dir/"
        fi
    done

    # 修改 install name 指向同目录下的 dylib（使用 @loader_path）
    for lib in $(otool -L "$dest_dir/$binary_name" 2>/dev/null | grep -E '^\s+/opt/homebrew|^\s+/usr/local/(Cellar|opt)' | awk '{print $1}' || true); do
        local lib_name
        lib_name="$(basename "$lib")"
        if [[ -f "$dest_dir/$lib_name" ]]; then
            install_name_tool -change "$lib" "@loader_path/$lib_name" "$dest_dir/$binary_name" 2>/dev/null || true
            echo "  ✓ 重定向 $lib_name → @loader_path/$lib_name"
        fi
    done
}

# ---------- 1. ffmpeg ----------
echo "--- ffmpeg ---"
FFMPEG_DEST="$THIRD_PARTY/ffmpeg"
if [[ -x "$FFMPEG_DEST/ffmpeg" ]]; then
    echo "  ✓ 已存在，跳过"
else
    FFMPEG_SRC=$(find_binary ffmpeg) || true
    if [[ -n "${FFMPEG_SRC:-}" ]]; then
        copy_with_dylibs "$FFMPEG_SRC" "$FFMPEG_DEST"
    else
        echo "  ⚠ 未找到 ffmpeg，请先通过 Homebrew 安装: brew install ffmpeg"
    fi
fi

# ---------- 2. MP4Box (gpac) ----------
echo "--- MP4Box (gpac) ---"
MP4BOX_DEST="$THIRD_PARTY/gpac"
if [[ -x "$MP4BOX_DEST/MP4Box" ]]; then
    echo "  ✓ 已存在，跳过"
else
    MP4BOX_SRC=$(find_binary MP4Box) || true
    if [[ -n "${MP4BOX_SRC:-}" ]]; then
        copy_with_dylibs "$MP4BOX_SRC" "$MP4BOX_DEST"
        # 同时复制 GPAC 模块目录
        local gpac_modules=""
        if command -v brew &>/dev/null; then
            gpac_modules="$(brew --prefix gpac 2>/dev/null)/lib/gpac"
        fi
        if [[ -z "$gpac_modules" || ! -d "$gpac_modules" ]]; then
            gpac_modules="/opt/homebrew/opt/gpac/lib/gpac"
        fi
        if [[ -d "$gpac_modules" ]]; then
            mkdir -p "$MP4BOX_DEST/gpac"
            cp -R "$gpac_modules/"* "$MP4BOX_DEST/gpac/" 2>/dev/null || true
            echo "  ✓ 复制 GPAC 模块 → $MP4BOX_DEST/gpac/"
        fi
    else
        echo "  ⚠ 未找到 MP4Box，请先通过 Homebrew 安装: brew install gpac"
    fi
fi

# ---------- 3. docker CLI ----------
echo "--- docker CLI ---"
DOCKER_DEST="$THIRD_PARTY/docker"
if [[ -x "$DOCKER_DEST/docker" ]]; then
    echo "  ✓ 已存在，跳过"
else
    DOCKER_SRC=$(find_binary docker) || true
    if [[ -n "${DOCKER_SRC:-}" ]]; then
        # docker CLI 通常是静态链接的，直接复制即可
        mkdir -p "$DOCKER_DEST"
        cp "$DOCKER_SRC" "$DOCKER_DEST/docker"
        chmod +x "$DOCKER_DEST/docker"
        echo "  ✓ 复制 docker → $DOCKER_DEST/docker"
    else
        echo "  ⚠ 未找到 docker，请先通过 Homebrew 安装: brew install docker"
    fi
fi

# ---------- 4. Colima + Lima ----------
echo "--- Colima + Lima ---"
COLIMA_DEST="$THIRD_PARTY/colima"
if [[ -x "$COLIMA_DEST/colima" ]] && [[ -x "$COLIMA_DEST/limactl" ]]; then
    echo "  ✓ 已存在，跳过"
else
    COLIMA_SRC=$(find_binary colima) || true
    LIMACTL_SRC=$(find_binary limactl) || true
    if [[ -n "${COLIMA_SRC:-}" ]] && [[ -n "${LIMACTL_SRC:-}" ]]; then
        mkdir -p "$COLIMA_DEST"
        cp "$COLIMA_SRC" "$COLIMA_DEST/colima"
        cp "$LIMACTL_SRC" "$COLIMA_DEST/limactl"
        chmod +x "$COLIMA_DEST/colima" "$COLIMA_DEST/limactl"
        echo "  ✓ 复制 colima → $COLIMA_DEST/colima"
        echo "  ✓ 复制 limactl → $COLIMA_DEST/limactl"

        # 复制 Lima 的 guest agent（虚拟机内通信必需）
        lima_prefix=""
        if command -v brew &>/dev/null; then
            lima_prefix="$(brew --prefix lima 2>/dev/null)"
        fi
        guest_agent="${lima_prefix}/share/lima/lima-guestagent.Linux-aarch64.gz"
        if [[ -f "$guest_agent" ]]; then
            mkdir -p "$COLIMA_DEST/share/lima"
            cp "$guest_agent" "$COLIMA_DEST/share/lima/"
            echo "  ✓ 复制 lima-guestagent → $COLIMA_DEST/share/lima/"
        fi

        # 复制 Lima 模板（可选）
        templates_dir="${lima_prefix}/share/lima/templates"
        if [[ -d "$templates_dir" ]]; then
            mkdir -p "$COLIMA_DEST/share/lima/templates"
            cp -R "$templates_dir/"* "$COLIMA_DEST/share/lima/templates/" 2>/dev/null || true
            echo "  ✓ 复制 Lima 模板 → $COLIMA_DEST/share/lima/templates/"
        fi
    else
        echo "  ⚠ 未找到 colima/limactl，请先通过 Homebrew 安装: brew install colima lima"
    fi
fi

echo ""
echo "=== 嵌入完成 ==="
echo "请确保以下文件已添加到 Xcode 项目资源中："
echo "  ThirdParty/ffmpeg/"
echo "  ThirdParty/gpac/"
echo "  ThirdParty/docker/"
echo "  ThirdParty/colima/"
