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
    local FOUND=0
    if [ -n "$REPO" ] && [ -f "$REPO/scripts/build_ipa_from_nsp.py" ]; then
        FOUND=1
    fi

    if [ "$FOUND" -eq 0 ]; then
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
                FOUND=1
                break
            fi
        done
    fi

    if [ "$FOUND" -eq 0 ]; then
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
    fi

    # Sync bundled configs, shader lists, mods, and patches into the engine
    local RES="${BUNDLE_RESOURCES:-$(cd "$(dirname "$0")/.." && pwd)}"
    if [ ! -d "$RES/config" ] && [ -d "$(dirname "$0")/config" ]; then
        RES="$(dirname "$0")"
    fi

    local GAME_DIR="$REPO/dm/games/0400486024DEC000"
    mkdir -p "$GAME_DIR"

    if [ -d "$RES/config" ]; then
        echo "  ✓ Syncing game configs & shader manifests from bundle..."
        cp -f "$RES/config/game.tsv" "$GAME_DIR/game.tsv" 2>/dev/null || true
        cp -f "$RES/config/settings.tsv" "$REPO/dm/games/settings.tsv" 2>/dev/null || true
        cp -f "$RES/config/mac_env.txt" "$REPO/mac_env.txt" 2>/dev/null || true
        if [ -f "$RES/config/shader_seen.tsv" ]; then
            cp -f "$RES/config/shader_seen.tsv" "$GAME_DIR/shader_seen.tsv"
        fi
        if [ -f "$RES/config/shader_seen_full.tsv" ]; then
            cp -f "$RES/config/shader_seen_full.tsv" "$GAME_DIR/shader_seen_full.tsv"
            if [ ! -f "$GAME_DIR/shader_seen.tsv" ]; then
                cp -f "$RES/config/shader_seen_full.tsv" "$GAME_DIR/shader_seen.tsv"
            fi
        fi
    fi

    if [ -d "$RES/romfs_mods" ]; then
        echo "  ✓ Syncing RomFS keyboard and prompt assets..."
        cp -f "$RES/romfs_mods/"* "$GAME_DIR/" 2>/dev/null || true
    fi

    if [ -d "$RES/tools" ]; then
        cp -f "$RES/tools/"* "$REPO/dm/tools/" 2>/dev/null || true
    fi

    # Apply Ninboy Hat engine patch if git repo and clean
    if [ -f "$RES/patches/ninboy-hat-macos.patch" ] && [ -d "$REPO/.git" ]; then
        (cd "$REPO" && git apply --check "$RES/patches/ninboy-hat-macos.patch" 2>/dev/null && git apply "$RES/patches/ninboy-hat-macos.patch" 2>/dev/null || true)
    fi
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
    local SEEN_FLAG=""
    if [ -f "$REPO/dm/games/0400486024DEC000/shader_seen.tsv" ]; then
        SEEN_FLAG="--seen-shaders"
        echo "  ✓ Using targeted shader list (shader_seen.tsv)" | tee -a "$LOG"
    else
        echo "  ! shader_seen.tsv not found; translating full shader catalog" | tee -a "$LOG"
    fi
    "$PY" "$REPO/scripts/build_ipa_from_nsp.py" "$NUP" \
        --platform mac \
        --work-dir "$WORK" \
        --keep-extracted \
        $SEEN_FLAG \
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
    local SEEN_FLAG=""
    if [ -f "$REPO/dm/games/0400486024DEC000/shader_seen.tsv" ]; then
        SEEN_FLAG="--seen-shaders"
    fi
    "$PY" "$REPO/scripts/build_ipa_from_nsp.py" "$NUP" \
        --platform mac-app \
        --work-dir "$WORK" \
        --keep-extracted \
        $SEEN_FLAG \
        --allow-damaged \
        --allow-other-metal \
        --env-file "$REPO/mac_env.txt" \
        -o "$APP" 2>&1 | tee -a "$LOG"

    # Ensure macOS Game Mode and Controller support flags are enabled in Info.plist
    plutil -replace LSSupportsGameMode -bool true "$APP/Contents/Info.plist" 2>/dev/null || true
    plutil -replace GCSupportsGameMode -bool true "$APP/Contents/Info.plist" 2>/dev/null || true
    plutil -replace GCSupportsControllerUserInteraction -bool true "$APP/Contents/Info.plist" 2>/dev/null || true
    plutil -replace LSApplicationCategoryType -string "public.app-category.games" "$APP/Contents/Info.plist" 2>/dev/null || true
    plutil -replace NSPrincipalClass -string "NSApplication" "$APP/Contents/Info.plist" 2>/dev/null || true

    # Strip quarantine attributes to prevent Gatekeeper timeout/stalls
    xattr -cr "$APP" 2>/dev/null || true

    # Re-sign executable and bundle
    codesign -f -s - "$APP/Contents/MacOS/nxnative" 2>/dev/null || true
    codesign -f -s - "$APP"
    echo "==> App packaged & signed: $APP" | tee -a "$LOG"

    # Register into LaunchServices database
    local LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    if [ -x "$LSREG" ]; then
        "$LSREG" -f "$APP" 2>/dev/null || true
    fi

    # macOS Game Mode Integration: register app bookmark into LSIdentifiedGame
    swift - "$APP" << 'EOF' 2>/dev/null || true
import Foundation
let args = CommandLine.arguments
guard args.count > 1 else { exit(0) }
let appPath = args[1]
let bundleID = "org.nxnative.0400486024dec000"
let lsPlistPath = ("~/Library/Preferences/com.apple.LaunchServices/com.apple.LaunchServices.plist" as NSString).expandingTildeInPath
do {
    let url = URL(fileURLWithPath: appPath)
    let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    let plistData = try Data(contentsOf: URL(fileURLWithPath: lsPlistPath))
    if var dict = try PropertyListSerialization.propertyList(from: plistData, options: .mutableContainersAndLeaves, format: nil) as? [String: Any] {
        var games = dict["LSIdentifiedGame"] as? [String: Any] ?? [:]
        games[bundleID] = [bookmark, 3]
        dict["LSIdentifiedGame"] = games
        let outData = try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
        try outData.write(to: URL(fileURLWithPath: lsPlistPath))
    }
} catch {}
EOF

    # If the app is installed outside /Applications and ~/Applications, link it into ~/Applications for gamepolicyd detection
    if [[ "$APP" != /Applications/* ]] && [[ "$APP" != "$HOME/Applications/"* ]]; then
        mkdir -p "$HOME/Applications"
        ln -sfn "$APP" "$HOME/Applications/Ocarina of Time.app" 2>/dev/null || true
        if [ -x "$LSREG" ]; then
            "$LSREG" -f "$HOME/Applications/Ocarina of Time.app" 2>/dev/null || true
        fi
        echo "==> Registered Game Mode link in $HOME/Applications/Ocarina of Time.app" | tee -a "$LOG"
    fi

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
