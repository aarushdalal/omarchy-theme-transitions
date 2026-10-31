# omarchy-theme-transitions 1.5.0

### Highlights

- **Interactive 3D Motion, Theme Harmony Swatches & Favoriting Suite**:
  - **Dynamic 3D Parallax Tilt & Specular Light Sheen**: The hero card reacts dynamically to mouse coordinates with real-time 3D perspective tilt ($X$ and $Y$ rotation axes) and an interactive specular glass light sheen across the surface.
  - **Theme Color Harmony Swatches**: `omarchy-theme-switcher` extracts palette colors (`accent`, `bg`, `fg`) and outputs them into `.rows.tsv`; `ImagePickerModel.js` parses the palette, and the hero dock renders dynamic color dots in a frosted pill.
  - **Theme Favoriting & Star Pinning**: Clickable star button (`★`/`☆`) and `Ctrl+S` shortcut with persistent storage in `~/.local/state/omarchy/favorite-themes.json`.
  - **Favorites-Only Deck Filter**: Toggle button in the top HUD (`★ Favorites`) to isolate and browse only starred favorite themes.
  - **Surprise Me / Roulette Shuffle**: Interactive shuffle button (`󰒝`) in top HUD and `Ctrl+R` shortcut to quickly discover and animate to a random theme.
  - **Immersive Fullscreen Wallpaper Peeking**: Fullscreen button (`󰍹`) or `Space` key cleanly fades all chrome and expands the wallpaper to full screen with a subtle exit pill.
  - **Acoustic Mechanical Tick Feedback**: Mechanical audio click on card flips and scrubbing using `canberra-gtk-play`, toggleable with `Ctrl+M` or the audio button.
  - **Touchpad & Mouse Wheel Navigation**: Native `WheelHandler` support for smooth two-finger touchpad swiping and mouse wheel navigation across the deck.
  - **Refined Shortcuts HUD**: Polished shortcuts dock with clear badges for all deck interactions (`◄ ► Deck`, `Enter Apply`, `Space Peek`, `Ctrl+R Shuffle`, `Ctrl+S Star`, `Ctrl+M Sound`, `Esc Close`).

### Included Features & Enhancements

- **Prismatic 3D Amphitheater Arc Deck Reference**: Flanking cards fan outward and curve downward in a crescent arc to keep the central hero card commanding and unblocked at the top.
- **Hardware-Accelerated Anti-Aliased Clipping**: GPU `MultiEffect` alpha masks prevent rectangular image corners from bleeding past the rounded card borders.
- **Progressive 4K Master Wallpaper Pipeline**: Instant low-latency preview thumbnails decoupled from crystal-clear master full-resolution wallpapers on the active card.
- **Dynamic Horizon Ambient Backdrop**: Full-screen wallpaper aura blooming beneath the gallery with subtle obsidian vignette shading.
- **Tactile Deck Scrubber**: Timeline ribbon supporting instant drag and seek across 2,050+ wallpapers.

### Validation

- Privacy and payload validation: `python3 tools/release_privacy_check.py` (0 findings).
- Unit tests: `python3 -m unittest discover -s reference/wallpaper-manager/tests` (120 tests passed).
