# Manual Reference Port & Patch Guide

## Why this is packaged as a Reference Port

Modifying core shell internals directly (`~/.local/share/omarchy/shell` or `/usr/share/omarchy`) without a supported user-owned extension hook can cause divergence between upstream Omarchy shell updates and local files.

**This project is provided as a version-tested reference port for Omarchy 4.0.2 / Quickshell 0.3.1.**

## Architecture

- **Rendering Layer**: Strictly executed on `WlrLayer.Background` (`Layer level 0`), beneath application windows and above the wallpaper.
- **Double-Buffered VRAM Slot Architecture**: Utilizes two persistent image items (`slotA` and `slotB`) inside `Background.qml` to avoid disk reload stalls during transitions.
- **GLSL Fragment Shader**: `shaders/transition.frag` compiled to Qt Shader Baker format (`transition.frag.qsb`) via `/usr/lib/qt6/bin/qsb --qt6 --batchable`.

## Compilation Step

To compile the GLSL 440 fragment shader for Qt Quick 6:

```bash
/usr/lib/qt6/bin/qsb --qt6 --batchable -o shaders/transition.frag.qsb shaders/transition.frag
```
