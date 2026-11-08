#!/bin/bash
# ==============================================================================
# apply_mods_to_nup.sh - Inject Ninboy Hat macOS modifications into RomFS
# ==============================================================================
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -z "$1" ]; then
    echo "Usage: $(basename "$0") <path_to_work_dir_or_romfs_overlay>"
    echo "Example: $(basename "$0") ~/Documents/Switch\ 2\ Games/0400486024DEC000_build-kid/extract/v131072/romfs_overlay"
    exit 1
fi

DEST_DIR="$1"
mkdir -p "$DEST_DIR/UI/Layout2Archive" "$DEST_DIR/Font"

echo "==> Injecting Keyboard / Mouse Prompt Textures..."
cp -v "$ROOT_DIR/romfs_mods/Common_kbd.Product.100.Nin_Ounce_NVN2.bntx.zs" \
      "$DEST_DIR/UI/Layout2Archive/Common.Product.100.Nin_Ounce_NVN2.bntx.zs"

echo "==> Injecting Extended Keyboard Vector Font..."
cp -v "$ROOT_DIR/romfs_mods/External_kbd.Nin_Ounce_NVN2.bfotf.zs" \
      "$DEST_DIR/Font/External.Nin_Ounce_NVN2.bfotf.zs"

echo "==> Successfully installed Ninboy Hat RomFS modifications!"
