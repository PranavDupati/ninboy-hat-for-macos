#!/bin/bash
# ==============================================================================
# Native Port Builder: The Legend of Zelda: Ocarina of Time (Switch 2 -> macOS)
# Target: Apple Silicon M-Series (macOS 15+ / Metal 4)
# ==============================================================================
set -eo pipefail

REPO="${REPO:-$HOME/kid-with-sword-remake}"
PY="${PY:-$HOME/nxnative/.venv/bin/python3}"
GAMES_DIR="${GAMES_DIR:-$HOME/Documents/Switch 2 Games}"
NUP="$GAMES_DIR/The Legend of Zelda Ocarina of Time.nup"
WORK="$GAMES_DIR/0400486024DEC000_build-kid"
APP="$GAMES_DIR/Ocarina of Time.app"
LOG="$HOME/Downloads/oot-native-build.log"

export PATH="$HOME/.dotnet:$PATH"
export DOTNET_ROOT="$HOME/.dotnet"

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --all        Full build: base dev build, 720p/1080p overlays, and standalone .app (default)
  --app-only   Package standalone .app bundle only (reuses existing shader cache & build)
  --run        Launch the native macOS app immediately
  --clean      Clean build artifacts and temporary files
  --help       Show this message
EOF
    exit 0
}

build_base() {
    echo "==> [1/3] Base Build & Shader Translation" | tee -a "$LOG"
    "$PY" "$REPO/scripts/build_ipa_from_nsp.py" "$NUP" \
        --platform mac \
        --work-dir "$WORK" \
        --keep-extracted \
        --seen-shaders \
        --allow-damaged \
        --allow-other-metal \
        --env-file "$REPO/mac_env.txt" 2>&1 | tee -a "$LOG"
}

build_overlays() {
    echo "==> [2/3] Generating Flat Resolution Overlays (720p Handheld / 1080p Docked)" | tee -a "$LOG"
    local V="$WORK/extract/v131072"
    mkdir -p "$V/romfs_overlay/handheld" "$V/romfs_overlay/docked"
    "$PY" "$REPO/scripts/oot_res_overlay.py" "$V/RomFS.img" "$V/romfs_overlay/handheld" 0.666667 - flat 2>&1 | tee -a "$LOG"
    "$PY" "$REPO/scripts/oot_res_overlay.py" "$V/RomFS.img" "$V/romfs_overlay/docked" 0.9375 - flat 2>&1 | tee -a "$LOG"
}

package_app() {
    echo "==> [3/3] Packaging Standalone macOS App Bundle & Pipeline Archive" | tee -a "$LOG"
    "$PY" "$REPO/scripts/build_ipa_from_nsp.py" "$NUP" \
        --platform mac-app \
        --work-dir "$WORK" \
        --keep-extracted \
        --seen-shaders \
        --allow-damaged \
        --allow-other-metal \
        --env-file "$REPO/mac_env.txt" \
        -o "$APP" 2>&1 | tee -a "$LOG"

    # Re-sign with entitlements
    codesign -f -s - "$APP"
    echo "==> App packaged & signed: $APP" | tee -a "$LOG"
}

ACTION="${1:---all}"

case "$ACTION" in
    --all)
        echo "=== Native Port Build: Full Pipeline ($(date '+%H:%M:%S')) ===" | tee "$LOG"
        cd "$REPO"
        build_base
        build_overlays
        package_app
        echo "=== Build Complete: $APP ($(date '+%H:%M:%S')) ===" | tee -a "$LOG"
        ;;
    --app-only)
        echo "=== Packaging App Only ($(date '+%H:%M:%S')) ===" | tee "$LOG"
        cd "$REPO"
        package_app
        ;;
    --run)
        echo "==> Launching: $APP"
        open "$APP"
        ;;
    --clean)
        echo "==> Cleaning build artifacts..."
        rm -rf "$WORK" "$HOME/Downloads/oot-native-build.log"
        echo "==> Clean complete."
        ;;
    --help|-h)
        usage
        ;;
    *)
        echo "Error: Unknown option '$ACTION'"
        usage
        ;;
esac
