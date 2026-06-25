#!/usr/bin/env bash
# package_gpac_runtime.sh — 生成 Apple Music managed runtime 使用的 GPAC/MP4Box 包。
# 默认从 Homebrew/PATH 找 MP4Box，递归复制非系统 dylib，并重写为 @loader_path。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="${1:-$ROOT_DIR/build/gpac-runtime.tar.gz}"
WORK_DIR="$ROOT_DIR/build/gpac-runtime-work"
STAGE="$WORK_DIR/gpac-runtime"

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

is_portable_dependency() {
    [[ "$1" =~ ^/opt/homebrew ]] || [[ "$1" =~ ^/usr/local/(Cellar|opt) ]]
}

copy_and_rewrite() {
    local src="$1"
    local dest="$2"
    local name
    name="$(basename "$dest")"

    if [[ ! -f "$dest" ]]; then
        cp "$src" "$dest"
        chmod u+w "$dest"
        if [[ -x "$src" ]]; then chmod +x "$dest"; else chmod 644 "$dest"; fi
        echo "  ✓ $name"
    fi

    if [[ "$name" == *.dylib ]]; then
        install_name_tool -id "@loader_path/$name" "$dest" 2>/dev/null || true
    fi

    while IFS= read -r lib; do
        [[ -n "$lib" ]] || continue
        if is_portable_dependency "$lib"; then
            local lib_name="$(_basename "$lib")"
            local copied="$STAGE/$lib_name"
            copy_and_rewrite "$lib" "$copied"
            install_name_tool -change "$lib" "@loader_path/$lib_name" "$dest" 2>/dev/null || true
        fi
    done < <(otool -L "$src" 2>/dev/null | awk 'NR > 1 {print $1}')
}

_basename() {
    basename "$1"
}

rm -rf "$WORK_DIR"
mkdir -p "$STAGE"

MP4BOX_SRC="$(find_binary MP4Box)"
copy_and_rewrite "$MP4BOX_SRC" "$STAGE/MP4Box"

GPAC_MODULES=""
if command -v brew &>/dev/null; then
    GPAC_MODULES="$(brew --prefix gpac 2>/dev/null || true)/lib/gpac"
fi
if [[ -z "$GPAC_MODULES" || ! -d "$GPAC_MODULES" ]]; then
    GPAC_MODULES="/opt/homebrew/opt/gpac/lib/gpac"
fi
if [[ -d "$GPAC_MODULES" ]]; then
    mkdir -p "$STAGE/gpac"
    cp -R "$GPAC_MODULES/"* "$STAGE/gpac/" 2>/dev/null || true
    for module in "$STAGE"/gpac/*.dylib; do
        [[ -f "$module" ]] || continue
        while IFS= read -r lib; do
            [[ -n "$lib" ]] || continue
            if is_portable_dependency "$lib"; then
                lib_name="$(_basename "$lib")"
                copy_and_rewrite "$lib" "$STAGE/$lib_name"
                install_name_tool -change "$lib" "@loader_path/../$lib_name" "$module" 2>/dev/null || true
            fi
        done < <(otool -L "$module" 2>/dev/null | awk 'NR > 1 {print $1}')
    done
fi

mkdir -p "$(dirname "$OUTPUT")"
tar -czf "$OUTPUT" -C "$WORK_DIR" gpac-runtime
echo "GPAC runtime package: $OUTPUT"
