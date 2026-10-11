# Manual Reference Port & Patch Guide

## Why this is packaged as a Reference Port

Modifying core shell internals directly (`~/.local/share/omarchy/shell` or `/usr/share/omarchy`) without a supported user-owned extension hook can cause divergence between upstream Omarchy shell updates and local files.

**This project is provided as a version-tested reference port for Omarchy 4.0.2 / Quickshell 0.3.1.**

## Architecture

- **Rendering Layer**: Strictly executed on `WlrLayer.Background` (`Layer level 0`), beneath application windows and above the wallpaper.
- **Double-Buffered VRAM Slot Architecture**: Utilizes two persistent image items (`slotA` and `slotB`) inside `Background.qml` to avoid disk reload stalls during transitions.
- **GLSL Fragment Shader**: `shaders/transition.frag` compiled to Qt Shader Baker format (`transition.frag.qsb`) via `/usr/lib/qt6/bin/qsb --qt6 --batchable`.

## Components in `reference/`

- **`reference/Background.qml`**: Reference port for `~/.local/share/omarchy/shell/plugins/background/Background.qml` featuring the double-buffered VRAM slot architecture and GLSL 440 transition shader bindings.
- **`reference/ImagePicker.qml`**: Reference port for `~/.local/share/omarchy/shell/plugins/image-picker/ImagePicker.qml` providing the widescreen 16:9 hero card layout, 26px rounded corners, floating frosted info dock, and fluid spring physics.

## Compilation Step

To compile the GLSL 440 fragment shader for Qt Quick 6:

```bash
/usr/lib/qt6/bin/qsb --qt6 --batchable -o shaders/transition.frag.qsb shaders/transition.frag
```

## User-owned integration

These files are a reference port, not an automatic core-shell installer. Do not
overwrite a packaged shell to apply them. Use `omarchy plugin clone` for the
background and image picker, then adapt the cloned plugins to the shared provider.
Keep the singleton and `ThemeTransition.js` together and register the singleton in
the user module. `Background.qml` resolves its shader at `shaders/transition.frag.qsb`
relative to that component: the shader belongs inside the cloned background
plugin's `shaders/` directory. Preserve the original plugin manifest and IPC alias.

Compile and preview the cloned integration before enabling it. Back up existing
user configuration first. This update does not restart a live shell or change the
selected transition, wallpaper or theme.
