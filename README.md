# Omarchy Theme Transitions (`omarchy-theme-transitions`)

> **Unofficial / Experimental Project**: An independent reference implementation of signature GPU-accelerated theme transition animations for Omarchy Quickshell.

A GLSL 440 theme transition engine providing 8 continuous visual transition modes rendered on `WlrLayer.Background` beneath running desktop applications — with a dual-slot zero-copy VRAM architecture and a dedicated CLI for mode management.

This project was developed through an AI-assisted workflow. The concept, customization, configuration, testing, integration, and final iteration were directed and carried out by me.

---

## My Contribution

I did not write Omarchy, Quickshell, or Hyprland from scratch. What I contributed:

- **GLSL Fragment Shader**: Authored and iteratively optimized `shaders/transition.frag` — a GLSL 440 fragment shader implementing 8 distinct per-pixel transition algorithms: `color-morph`, `aurora-flow`, `ink-spread`, `prism-shift`, `liquid-transform`, `atmospheric-fade`, `material-repaint`, and `reality-shift`. Compiled to `transition.frag.qsb` via Qt Shader Baker (`qsb --qt6 --batchable`).
- **GPU Performance Optimization**: Replaced `pow(d, 2.0)` transcendental calls with single-cycle `d * d` multiplication for locked 60 FPS on AMD Radeon Vega integrated graphics. Eliminated duplicate `texture()` samplers to reduce GPU memory bandwidth.
- **Dual-Slot VRAM Architecture**: Designed the `slotA`/`slotB` zero-copy ping-pong image buffer pattern inside `Background.qml`, keeping both outgoing and incoming wallpapers resident in VRAM to eliminate transition start-lag and texture reload hitching.
- **Layer 0 Placement**: Strictly placed all transition rendering on `WlrLayer.Background` (Layer level 0) — beneath all running application windows — so transitions never occlude active terminal, browser, or IDE windows.
- **ThemeTransition.qml Singleton**: Authored `Commons/ThemeTransition.qml` for gamma-corrected perceptual color interpolation, dark/light polarity protection, mode persistence, and reduced-motion bypass.
- **CLI Tool**: Designed and implemented `bin/omarchy-theme-transition` with subcommands: `get`, `set <mode>`, `list`, and `preview [mode]`.
- **Reference Port**: Packaged changes as a documented reference port (not an automated shell-file replacer) in `reference/` and `docs/MANUAL-INSTALLATION.md` so users can apply changes safely with explicit review.
- **Installer**: Authored `./install.sh` for CLI deployment.
- **Testing**: Tested all 8 modes on Omarchy 4.0.2 / Quickshell 0.3.1 / Hyprland 0.56.2 / AMD Vega GPU at 60 Hz 1080p.

---

## Based On / Credits

- **[Omarchy](https://github.com/basecamp/omarchy)** — The open-source Arch Linux desktop environment by Basecamp. `Background.qml` and the theme switching pipeline are Omarchy components that this project extends via a reference port patch.
- **[Quickshell](https://quickshell.outfoxxed.me)** — The Qt6 QML Wayland layer-shell desktop shell. The GLSL shader is compiled and deployed for Quickshell's Qt6 scene graph shader pipeline.
- **[Hyprland](https://hyprland.org)** — The Wayland tiling compositor. `WlrLayer.Background` placement is a Quickshell Hyprland layer-shell API feature.
- **Qt Shader Baker (`qsb`)** — Part of `qt6-shadertools`. Used to compile GLSL 440 source to multi-target SPIR-V bytecode (`.qsb`) for the Qt6 RHI pipeline.

**Related Repos**:
- [omarchy-aesthetic-themes](https://github.com/aarushdalal/omarchy-aesthetic-themes) — 15 anime color themes that use these transitions
- [omarchy-motion-presets](https://github.com/aarushdalal/omarchy-motion-presets) — Hyprland animation preset collection
- [omarchy-shell-polish](https://github.com/aarushdalal/omarchy-shell-polish) — Frosted glass, floating bar, and keybinding snippets

---

## Technical Architecture

- **Omarchy**: `dev (13f18b2c) / 4.0.2`
- **Quickshell**: `0.3.1`
- **Compositor**: Hyprland `0.56.2`
- **Toolkit**: Qt 6.8+ (Qt Quick)
- **Shader Language**: GLSL 440 compiled via `qsb --qt6 --batchable`
- **Layer Placement**: Strictly `WlrLayer.Background` (Layer level 0) — above wallpaper, beneath all applications

---

## Transition Modes

| Mode | Description |
|---|---|
| `color-morph` | Smooth per-pixel palette interpolation across the entire screen |
| `aurora-flow` | Flowing aurora-borealis-like color wave sweep |
| `ink-spread` | Organic ink diffusion spreading from a center point |
| `prism-shift` | Prismatic RGB channel offset and blend |
| `liquid-transform` | Heavy liquid pour and settle |
| `atmospheric-fade` | Soft atmospheric cross-fade with bloom |
| `material-repaint` | Surface repaint wipe with material edge |
| `reality-shift` | Geometric reality-tear dissolve |

---

## Features

- **8 Signature Transition Modes**: GPU GLSL per-pixel math, 60 FPS locked
- **Zero-Occlusion Design**: Renders on `WlrLayer.Background` — never covers running apps
- **Double-Buffered VRAM Slot Architecture**: `slotA`/`slotB` ping-pong eliminates start-lag
- **Optimized Shader Math**: `d * d` instead of `pow(d, 2.0)` for integrated GPU performance
- **Dedicated CLI**: `omarchy-theme-transition` for inspecting, selecting, and previewing modes

---

## Requirements

- **Arch Linux** (x86_64)
- **Omarchy** `dev (13f18b2c) / 4.0.2` with **Quickshell** `0.3.1`
- **`qt6-shadertools`** (providing `/usr/lib/qt6/bin/qsb`)

---

## Compatibility

Tested exclusively against Omarchy 4.0.2 / Quickshell 0.3.1. Other versions may require adjusting QML component bindings.

---

## Installation & Reference Port Guide

```bash
git clone https://github.com/aarushdalal/omarchy-theme-transitions.git
cd omarchy-theme-transitions

# Install the CLI utility
./install.sh install
```

Read `docs/MANUAL-INSTALLATION.md` for applying the reference port to your Quickshell background plugin safely.

> **Important**: This project ships as a reference port — **not** an automated core-file replacer. Review `docs/MANUAL-INSTALLATION.md` carefully before applying patches to `~/.local/share/omarchy/shell/plugins/background/`.

---

## Commands

```bash
omarchy-theme-transition get               # Display active transition mode
omarchy-theme-transition list              # List all 8 transition modes
omarchy-theme-transition set aurora-flow   # Set mode to aurora-flow
omarchy-theme-transition preview [mode]    # Preview transition without changing active theme
```

---

## Compiling the Shader

If you modify `shaders/transition.frag`, recompile to `.qsb` before deploying:

```bash
/usr/lib/qt6/bin/qsb --qt6 --batchable -o shaders/transition.frag.qsb shaders/transition.frag
```

---

## License

[MIT License](LICENSE).

---

## Credits / Third-Party Notices

- Built for the [Omarchy](https://github.com/basecamp/omarchy) desktop environment.
- Powered by [Quickshell](https://quickshell.outfoxxed.me/) and [Hyprland](https://hyprland.org/).
- Shader compiled with Qt Shader Baker (`qt6-shadertools`).
- Not an official Omarchy product.
