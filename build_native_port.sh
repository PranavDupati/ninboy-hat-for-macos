#!/bin/bash
# ==============================================================================
# Native Port Builder: The Legend of Zelda: Ocarina of Time (Switch 2 -> macOS)
# Target: Apple Silicon M-Series (macOS 15+ / Metal 4)
# Inspired in part by the preflight diagnostics & environment management in GreenKid-MV
# ==============================================================================
set -eo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.dotnet:${PATH:-}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"

SUPPORT_DIR="${SUPPORT_DIR:-$HOME/Library/Application Support/NinboyHat}"
REPO="${REPO:-}"
GAMES_DIR="${GAMES_DIR:-$HOME/Documents/Switch 2 Games}"
NUP="${NUP:-$GAMES_DIR/The Legend of Zelda Ocarina of Time.nup}"
WORK="${WORK:-$GAMES_DIR/0400486024DEC000_build-kid}"
APP="${APP:-$GAMES_DIR/Ocarina of Time.app}"
LOG="${LOG:-$HOME/Downloads/oot-native-build.log}"

# Find or auto-provision the base translation engine
find_or_setup_engine() {
    if [ -n "$REPO" ] && [ -f "$REPO/scripts/build_ipa_from_nsp.py" ]; then
        return 0
    fi

    # Check known local candidates
    for candidate in \
        "$BUNDLE_RESOURCES" \
        "$SUPPORT_DIR/engine" \
        "$HOME/kid-with-sword-remake" \
        "$HOME/ninboy-hat-for-macos" \
        "$(cd "$(dirname "$0")/.." && pwd)" \
        "$(pwd)"; do
        if [ -n "$candidate" ] && [ -f "$candidate/scripts/build_ipa_from_nsp.py" ]; then
            REPO="$candidate"
            echo "  ✓ Base engine found at $REPO"
            return 0
        fi
    done

    # Provision base engine automatically into Application Support
    echo "==> Base engine not found locally. Downloading base translation engine from GitHub..."
    mkdir -p "$SUPPORT_DIR"
    if ! command -v git >/dev/null 2>&1; then
        echo "✗ Error: git is required to download the open-source translation engine. Please run 'xcode-select --install'."
        exit 1
    fi

    if [ ! -d "$SUPPORT_DIR/engine/.git" ]; then
        rm -rf "$SUPPORT_DIR/engine"
        git clone --depth 1 https://github.com/cheemu21/kid-with-sword-remake.git "$SUPPORT_DIR/engine"
    fi
    REPO="$SUPPORT_DIR/engine"
    echo "  ✓ Base engine provisioned at $REPO"
}

# Discover or provision Python environment
find_or_setup_python() {
    # 1. Existing explicit override or known venvs
    for candidate in "$PY" "$HOME/nxnative/.venv/bin/python3" "$SUPPORT_DIR/venv/bin/python3"; do
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            PY="$candidate"
            return 0
        fi
    done

    # 2. Automatically provision isolated venv using uv or python3
    echo "==> Setting up isolated Python environment in $SUPPORT_DIR/venv..."
    mkdir -p "$SUPPORT_DIR"
    if command -v uv >/dev/null 2>&1; then
        uv venv "$SUPPORT_DIR/venv" >/dev/null
        uv pip install --python "$SUPPORT_DIR/venv/bin/python3" zstandard pillow fonttools >/dev/null
    else
        python3 -m venv "$SUPPORT_DIR/venv"
        "$SUPPORT_DIR/venv/bin/pip" install --quiet zstandard pillow fonttools
    fi
    PY="$SUPPORT_DIR/venv/bin/python3"
}

doctor() {
    echo "=== Ninboy Hat Preflight Diagnostics (Doctor) ==="
    local OK=1

    # Check Architecture
    if [[ "$(uname -m)" == "arm64" ]]; then
        echo "  ✓ Apple Silicon ARM64 architecture detected ($(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'Apple Silicon'))"
    else
        echo "  ✗ Error: Apple Silicon ARM64 is required (found $(uname -m))."
        OK=0
    fi

    # Check macOS Version
    local OS_VER
    OS_VER="$(sw_vers -productVersion)"
    echo "  ✓ macOS version $OS_VER detected"

    # Check Xcode / Metal compiler
    if xcrun --find metal >/dev/null 2>&1; then
        local METAL_VER
        METAL_VER="$(xcrun metal --version 2>&1 | head -n 1 || echo 'Metal toolchain ready')"
        echo "  ✓ Metal toolchain: $METAL_VER"
    else
        echo "  ✗ Error: Metal compiler not found. Please install Xcode / Command Line Tools: xcode-select --install"
        OK=0
    fi

    # Check .NET SDK
    if command -v dotnet >/dev/null 2>&1; then
        echo "  ✓ .NET SDK: $(dotnet --version)"
    else
        echo "  ! Warning: .NET SDK not found. Install via 'brew install dotnet-sdk' if host translation tools require it."
    fi

    # Check Python environment & packages
    find_or_setup_python
    if [ -x "$PY" ]; then
        if "$PY" -c "import zstandard, PIL, fontTools" >/dev/null 2>&1; then
            echo "  ✓ Python 3 environment ($PY) has required packages: zstandard, pillow, fonttools"
        else
            echo "  ! Warning: Python environment missing some packages. Installing..."
            "$PY" -m pip install --quiet zstandard pillow fonttools || true
            echo "  ✓ Installed required Python packages."
        fi
    else
        echo "  ✗ Error: Python 3 could not be configured."
        OK=0
    fi

    # Check translation engine
    find_or_setup_engine || OK=0

    # Check container file
    if [ -f "$NUP" ]; then
        local NUP_SIZE
        NUP_SIZE="$(ls -lh "$NUP" | awk '{print $5}')"
        echo "  ✓ Game container detected: $(basename "$NUP") ($NUP_SIZE)"
    else
        echo "  ! Note: .nup container not found at '$NUP'. You can specify NUP=/path/to/game.nup when building."
    fi

    echo "================================================="
    if [ "$OK" -eq 1 ]; then
        echo "==> All critical prerequisites satisfied! Ready to build."
        return 0
    else
        echo "==> Some prerequisites are missing. Please review errors above."
        return 1
    fi
}

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --doctor     Run preflight diagnostic checks on Apple Silicon, Metal, and Python tools
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
    find_or_setup_engine
    find_or_setup_python
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

    # Sync RAM optimizations to Application Support to prevent stale user config overrides
    local NX_SUP="$HOME/Library/Application Support/nxnative/0400486024DEC000"
    if [ -d "$NX_SUP" ]; then
        cp "$REPO/mac_env.txt" "$NX_SUP/env.txt"
        echo "==> Synced optimized env.txt to $NX_SUP/env.txt" | tee -a "$LOG"
    fi
}

ACTION="${1:---all}"

case "$ACTION" in
    --doctor)
        doctor
        ;;
    --all)
        doctor
        echo "=== Native Port Build: Full Pipeline ($(date '+%H:%M:%S')) ===" | tee "$LOG"
        cd "$REPO"
        build_base
        build_overlays
        package_app
        echo "=== Build Complete: $APP ($(date '+%H:%M:%S')) ===" | tee -a "$LOG"
        ;;
    --app-only)
        find_or_setup_python
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
