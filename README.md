# Omarchy Theme Transitions (`omarchy-theme-transitions`)

> **Unofficial / Experimental Project**: An independent reference implementation of signature theme transition animations for Omarchy Quickshell.

A GPU-accelerated theme transition engine providing 8 continuous visual transition modes rendered on Wayland `WlrLayer.Background` beneath running desktop applications.

---

## Status / Experimental Warning

This project touches desktop shell rendering. **It is packaged as a documented reference port and patch rather than an automated installer**, ensuring that core Omarchy shell files (`/usr/share/omarchy/` or `~/.local/share/omarchy/shell`) are never replaced automatically without explicit user review.

---

## Tested Versions & Technical Architecture

- **Omarchy**: `dev (13f18b2c) / 4.0.2`
- **Quickshell**: `0.3.1`
- **Compositor**: Hyprland `0.56.2`
- **Toolkit**: Qt 6.8+ (Qt Quick)
- **Shader Language**: GLSL 440 compiled via Qt Shader Baker (`qsb --qt6 --batchable`)
- **Layer Placement**: Strictly `WlrLayer.Background` (`Layer level 0`). Stacks directly above wallpaper and beneath all applications.

---

## Features

- **8 Signature Transition Modes**: `color-morph`, `aurora-flow`, `ink-spread`, `prism-shift`, `liquid-transform`, `atmospheric-fade`, `material-repaint`, `reality-shift`.
- **Zero-Occlusion Design**: Renders beneath open terminal, browser, and IDE windows so active work is never obscured.
- **Double-Buffered Slot Architecture**: Dual-slot `slotA`/`slotB` image buffers inside `Background.qml` keep outgoing and incoming backgrounds resident in VRAM to eliminate start-lag and texture reload hitching.
- **Optimized Shader Math**: Uses single-cycle arithmetic instead of transcendental power functions for smooth 60 FPS playback on integrated graphics.
- **Dedicated CLI**: `omarchy-theme-transition` for inspecting, selecting, and previewing modes.

---

## Requirements

- Arch Linux (x86_64)
- Omarchy `dev (13f18b2c) / 4.0.2` with Quickshell `0.3.1`
- `qt6-shadertools` (providing `/usr/lib/qt6/bin/qsb`)

---

## Compatibility

Tested exclusively against Omarchy 4.0.2 / Quickshell 0.3.1. Other versions may require adjusting QML component bindings.

---


## 🎬 Demo

**Live theme transition in action:**

<video src="https://github.com/aarushdalal/omarchy-theme-transitions/raw/main/assets/showcase/wallpaper_switch_theme.mp4" controls width="100%"></video>

## Installation & Reference Port Guide

1. Install the CLI utility:
   ```bash
   git clone https://github.com/YOUR-USERNAME/omarchy-theme-transitions.git
   cd omarchy-theme-transitions
   ./install.sh install
   ```
2. Read `docs/MANUAL-INSTALLATION.md` for applying the reference port to your Quickshell background plugin safely.

---

## Commands

```bash
omarchy-theme-transition get               # Display active transition mode
omarchy-theme-transition list              # List all 8 transition modes
omarchy-theme-transition set aurora-flow   # Set mode to aurora-flow
omarchy-theme-transition preview [mode]    # Preview transition without changing active theme
```

---

## Showcase

> Visual previews, UI screenshots, and recordings for documentation and release verification.

### Main experience

<!-- Future image: assets/showcase/transitions-hero.png -->
<!-- ![Main desktop experience](assets/showcase/transitions-hero.png) -->

### Feature gallery

<!-- Future image: assets/showcase/transition-aurora-flow.png -->
<!-- ![transition-aurora-flow.png](assets/showcase/transition-aurora-flow.png) -->

<!-- Future image: assets/showcase/transition-ink-spread.png -->
<!-- ![transition-ink-spread.png](assets/showcase/transition-ink-spread.png) -->

<!-- Future image: assets/showcase/transition-prism-shift.png -->
<!-- ![transition-prism-shift.png](assets/showcase/transition-prism-shift.png) -->

<!-- Future image: assets/showcase/transition-liquid-transform.png -->
<!-- ![transition-liquid-transform.png](assets/showcase/transition-liquid-transform.png) -->

<!-- Future image: assets/showcase/transition-color-morph.png -->
<!-- ![transition-color-morph.png](assets/showcase/transition-color-morph.png) -->

<!-- Future image: assets/showcase/transition-reality-shift.png -->
<!-- ![transition-reality-shift.png](assets/showcase/transition-reality-shift.png) -->

<!-- Future image: assets/showcase/feature-07.png -->
<!-- ![Feature preview 7](assets/showcase/feature-07.png) -->

<!-- Future image: assets/showcase/feature-08.png -->
<!-- ![Feature preview 8](assets/showcase/feature-08.png) -->

<!-- Future image: assets/showcase/feature-09.png -->
<!-- ![Feature preview 9](assets/showcase/feature-09.png) -->

<!-- Future image: assets/showcase/feature-10.png -->
<!-- ![Feature preview 10](assets/showcase/feature-10.png) -->

### Motion and interaction

<!-- Future GIF: assets/showcase/interaction-01.gif -->
<!-- ![Interaction preview](assets/showcase/interaction-01.gif) -->

<!-- Future GIF: assets/showcase/interaction-02.gif -->
<!-- ![Transition preview](assets/showcase/interaction-02.gif) -->

### Video demonstrations

<!-- Future thumbnail: assets/showcase/video-01-thumbnail.png -->
<!-- [![Watch demo video](assets/showcase/video-01-thumbnail.png)](https://github.com/YOUR-USERNAME/PROJECT-NAME/releases) -->


---

## License

[MIT License](LICENSE).
