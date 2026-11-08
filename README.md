# Ninboy Hat for macOS

Native Apple Silicon (ARM64 / Metal 4) compilation enhancements, crash fixes, keyboard/mouse input overhaul, and performance optimizations for *The Legend of Zelda: Ocarina of Time* (Switch 2 / NVN2).

> [!IMPORTANT]
> **Legal Disclaimer:** This repository does **NOT** contain any copyrighted Nintendo game assets, binaries, ROMs, or decrypted code. The base `.nup` container file (`0400486024DEC000`, v131072) must be legally dumped and provided by the user from their own console. These files are open-source patches, tools, configurations, and assets designed to help the game run natively and smoothly on Apple Silicon macOS hardware.

---

## Overview

*Ninboy Hat for macOS* is a collection of enhancements, stability patches, and graphics/input overhauls built on top of the native Switch 2 AArch64 translation framework. By executing directly on Apple Silicon's ARM64 CPU and harnessing Apple's **Metal 4** graphics API, this project delivers fluid 60 FPS / unlocked gameplay, crisp high-resolution rendering, intuitive PC keyboard & mouse controls, and rock-solid stability.

---

## Key Features & Modifications

### 🎮 Keyboard & Mouse Integration with Adapted In-Game UI
- **Smooth Mouse Camera Control:** Direct mouse delta camera navigation with an in-game sensitivity slider (20% – 500%).
- **Ergonomic PC Keybinds:**
  - `W` / `A` / `S` / `D`: Smooth character locomotion
  - `Left Click`: Sword swing / Attack
  - `Right Click`: Shield defense
  - `Middle Click` or `Z`: Z-Targeting / Lock-on
  - `Space`: Roll / Jump / Action
  - `E`: Context interact / Open / Talk (`⏎` Return shortcut)
  - `Q`: Ocarina
  - `1` / `2` / `3` / `4`: Quick item & weapon slots
- **Adapted In-Game Button Prompts:**
  - Replaces the default gamepad diamond buttons (`A`, `B`, `X`, `Y`) with unhighlighted, cleanly styled Apple SF Symbols:
    - **A Action:** `⏎` (Return)
    - **B Cancel/Back:** `⌫` (Delete)
    - **X Auxiliary:** `␣` (Space)
    - **Y Primary:** `Left Click`
  - Eliminates prompt clipping and text overlapping with in-game action words (e.g. `⏎ Open`, `⌫ Put Away`).
  - Corrected upper directional arrows for clean HUD alignment.

### 🛠️ Critical Crash Fixes
1. **L-Key Crash (`Result 0xe15` / Unserved HID Service):**
   - Added high-level emulation (HLE) stubs for `nn::hid::IsOunceVibrationDeviceMounted`, `nn::hid::detail::IsVibrationMounted`, and fallback IPC session handlers, preventing fatal aborts when pressing `L`.
2. **Zelda's Lullaby Learning Crash (`SIGABRT 134`):**
   - Fixed an unrecognized selector exception (`-[NvPkg buffer]: unrecognized selector sent to instance`) occurring during texture view recycling by unwrapping packaged `MTLTexture` instances and implementing automatic selector forwarding.

### ⚡ Visual Fidelity & Performance Tweaks
- **Hyrule Castle & Village Missing Textures Fix:**
  - Resolved missing/transparent ground and wall textures in Hyrule Market and Castle by enabling `tex_flush_upload` and `tex_dirty_upload`, ensuring CPU-written terrain height and blend maps are properly committed to GPU memory.
  - Tuned texture memory disposal (`tex_release 1`) to retain required CPU-accessible pool buffers without visual corruption.
- **Navi Fairy Rendering:** Corrected additive blend equations and sRGB color format mappings for accurate, ethereal fairy illumination.
- **Overlapped Compute Dispatch:** Activated parallel compute pipeline execution (`DM_NVN_DISPATCH_OVERLAP=1`), reducing Kokiri Forest and castle frame times by 2–3 ms.
- **Complete Shader Pre-Translation (42,854 Shaders):**
  - Includes a comprehensive shader variant catalog (`shader_seen_full.tsv`) covering 100% of the game (all temples, cutscenes, effects, and boss encounters) to eliminate runtime pipeline compilation stutter.
- **Dynamic FPS Modes & Frame Generation:**
  - Toggle between **30 FPS Lock**, **60 FPS Lock**, and **Unlocked / Unlimited FPS**.
  - Integrated support for **Apple MetalFX Frame Interpolation** and **AMD FSR 4 Frame Generation / INT8 ML Upscaling**.
- **Fully Unlocked UI Settings:**
  - Removed restrictive environment file locks in the launcher menu, enabling full real-time customization alongside a **"Reset to Tested Defaults"** safety button.

---

## Repository Structure

```
ninboy-hat-for-macos/
├── README.md               # Documentation, usage guide, and credits
├── LICENSE                 # MIT Open-Source License
├── patches/
│   └── ninboy-hat-macos.patch  # Unified diff for engine & host translation layers
├── romfs_mods/
│   ├── Common_kbd.Product.100.Nin_Ounce_NVN2.bntx.zs  # Swizzled BC4 button textures
│   ├── External_kbd.Nin_Ounce_NVN2.bfotf.zs           # Custom vector glyph font
│   ├── nintendo_ext_kbd.ttf                           # Extended keyboard TrueType font
│   └── zs.zsdic                                       # Compression dictionary
├── tools/
│   ├── make_keytex_bntx.py # Generates NVN2 swizzled BC4 prompt textures
│   └── make_ext_font.py    # Builds Nintendo BFOTF vector font archive
├── config/
│   ├── game.tsv            # Optimized game profile & HLE settings
│   ├── settings.tsv        # Host launcher settings manifest
│   ├── mac_env.txt         # Metal 4 high-performance environment flags
│   └── shader_seen_full.tsv# Complete 42,854 shader pipeline catalog
└── scripts/
    ├── build_native_port.sh# Automated end-to-end native build & package script
    └── apply_mods_to_nup.sh# Script to apply RomFS overlay mods to working directory
```

---

## Requirements

- **Hardware:** Apple Silicon Mac (M1, M2, M3, M4 or later)
- **OS:** macOS 14.0 (Sonoma) or macOS 15.0+ (Sequoia) with Metal 4 support
- **Development Tools:**
  - Xcode Command Line Tools: `xcode-select --install`
  - Python 3.10+ with `pip install zstandard pillow fonttools`
  - .NET 8 or 9 SDK (`brew install dotnet-sdk`)
- **Base Game:** Legally dumped `.nup` container file (`The Legend of Zelda Ocarina of Time.nup`, v131072) from your own console.

---

## Getting Started

### 1. Applying the Patch to Upstream Source

Clone the native translation layer base repository and apply the unified patch:

```bash
git clone https://github.com/cheemu21/kid-with-sword-remake.git
cd kid-with-sword-remake

# Apply the Ninboy Hat patch
git apply /path/to/ninboy-hat-for-macos/patches/ninboy-hat-macos.patch
```

### 2. Injecting RomFS Keyboard & Font Mods

Overlay the custom keyboard textures and vector fonts:

```bash
./scripts/apply_mods_to_nup.sh "/path/to/work-dir/extract/v131072/romfs_overlay"
```

Or regenerate the assets directly using the provided tools:

```bash
python3 tools/make_keytex_bntx.py RomFS.img zs.zsdic Common_kbd.Product.100.Nin_Ounce_NVN2.bntx.zs
python3 tools/make_ext_font.py
```

### 3. Building and Packaging the Standalone `.app`

Run the automated build script:

```bash
./scripts/build_native_port.sh --all
```

Options:
- `--all`: Full pipeline (extract, translate shaders, build overlays, package `.app`).
- `--app-only`: Package standalone `.app` using cached shaders and build.
- `--run`: Launch the game immediately.
- `--clean`: Remove temporary build artifacts.

---

## Sources & Credits

This project builds upon the groundbreaking reverse engineering and native translation work of the open-source community:

- **[seedds/nxnative](https://github.com/seedds/nxnative)** — The foundational AArch64 translation layer and Switch HLE host architecture.
- **[cheemu21/kid-with-sword-remake](https://github.com/cheemu21/kid-with-sword-remake)** — Game-specific HLE overrides, NVN2 translation, and platform adaptations.
- **[UzenUPoZiTiV4ik/fsr4-native-macos](https://github.com/UzenUPoZiTiV4ik/fsr4-native-macos)** by **PoZiTiV4ik** ([@UzenUPoZiTiV4ik](https://github.com/UzenUPoZiTiV4ik)) and contributors ([@fourlexboehm](https://github.com/fourlexboehm), [@d45h71](https://github.com/d45h71)) — The native Apple Silicon Metal implementation of AMD FidelityFX Super Resolution 4 (FSR 4.1.2 INT8 ML upscaler & frame generation pipeline).
- **[@itsawful911 on X](https://x.com/itsawful911/status/2119149308444565564)** and the **Reddit `r/SwitchPirates2`** community — Performance tuning research, shader pipeline discovery, and stutter mitigation analysis.
- **Apple Developer** — [Metal & MetalFX Documentation](https://developer.apple.com/metal/) for spatial upscaling and frame interpolation APIs.

---

## License

The modifications, scripts, and patches in this repository are licensed under the [MIT License](LICENSE).  
*The Legend of Zelda: Ocarina of Time* is a trademark of Nintendo. This project is unaffiliated with and not endorsed by Nintendo.
