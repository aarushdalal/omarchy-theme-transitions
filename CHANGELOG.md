# Changelog

## [1.6.0] - 2026-11-02

- Refine the optional Wallpaper Manager with calmer materials, finite entrance/interaction motion, larger artwork and clear selection actions.
- Include the queued group editor repair: clearing and slow typing retain text/cursor through autosave and group-list refresh.
- Cache group counts in one aggregate pass and reveal offscreen inspector controls during keyboard navigation. Preserve target defaults, import/retry/history and Apply behavior.
- Add isolated presentation, unusual group-name, keyboard-scroll, compact layout and reduced-motion checks.

## [1.5.1] - 2026-11-01

- Show per-item loading and unavailable preview states without borrowing artwork from another selection; preserve same-item thumbnail fallback, explicit Apply and request serial guards.
- Correct preview diagnostics to the existing seven-card bound and bounded original-image decoding.
- Keep the optional Wallpaper Manager's five selectors compatible with the shell palette, focus, disabled states and Qt keyboard selection. Preserve desktop target defaults and library operations.
- Add isolated Qt preview/selection tests and Manager keyboard/material tests. The preview checks do not apply a real desktop theme.

## [1.5.0] - 2026-10-31

- **Interactive 3D Motion, Theme Harmony Swatches & Favoriting Suite**:
  - Add interactive 3D parallax cursor tracking ($X$ and $Y$ rotation axes) and a moving specular glass sheen across the active hero card.
  - Propagate theme palette metadata (`accent`, `bg`, `fg`) in `omarchy-theme-switcher` through `.rows.tsv` and render live color harmony swatches inside the hero dock.
  - Add theme favoriting with star button (`★`/`☆`) and `Ctrl+S` shortcut, persisted to `~/.local/state/omarchy/favorite-themes.json`.
  - Add Favorites-only filter mode toggle in the top floating island (`★ Favorites`), isolating starred themes across groups with sub-millisecond filtering.
  - Add "Surprise Me" roulette shuffle (`󰒝` / `Ctrl+R`) to quickly discover and animate to random wallpapers.
  - Add immersive fullscreen wallpaper peeking (`󰍹` / `Space`) that smoothly fades away all UI chrome and displays the full-resolution master wallpaper with an exit pill.
  - Add acoustic mechanical tick feedback via `canberra-gtk-play` on flips and scrubbing, toggleable via `Ctrl+M` or the audio button.
  - Integrate native Qt 6 `WheelHandler` for fluid touchpad swipe and mouse-wheel navigation across the deck.
  - Refine bottom shortcuts dock with clear badges (`◄ ► Deck`, `Enter Apply`, `Space Peek`, `Ctrl+R Shuffle`, `Ctrl+S Star`, `Ctrl+M Sound`, `Esc Close`).

## [1.4.0] - 2026-10-31

- **Prismatic 3D Amphitheater Arc Deck Reference**:
  - Implement the Prismatic 3D Arc Deck layout in `reference/ImagePicker.qml` with symmetrical downward crescent fanning, keeping the central hero card commanding and unblocked at the top.
  - Implement hardware-accelerated anti-aliased masking (`MultiEffect` with `radius: 24`), eliminating rectangular image corner bleed and ensuring silky-smooth rounded borders on all cards.
  - Decouple full-resolution 4K/1080p master wallpapers from instant-decode preview thumbnails in `omarchy-theme-switcher` and `omarchy-menu-images`, providing zero blur on the hero card while guaranteeing instantaneous startup and navigation across 2,050+ themes.
  - Add the dynamic ambient atmospheric horizon canvas, radial halo glow, tactile deck scrubber ribbon with click-to-seek, and floating frosted glass docks.
  - Enhance group picker, import batch model, and workspace reference integrations for robust collection management.

## [1.3.0] - 2026-10-31

- Add History → Retry failed with a preview and background confirmation. Retries preserve original folder, group, name, desktop and media settings.
- Exclude successful files and later recoveries; recognize identical sources moved to another drive by their recorded hash. Preserve explicit replace settings for unresolved failures.
- Keep separate queue drafts and historical receipts intact. Prevent overlapping retries in the same retry family, and offer unfinished items after an interrupted run.
- Add retry-specific backend and interface checks, plus a dark History header and footer.
- Move History to the common Add toolbar so job details and retry remain accessible when the import queue is empty.

## [1.2.1] - 2026-10-31

- Check configured backup destinations before starting image processing. Keep the unsubmitted draft when a setup requirement fails, instead of repeating the same failure for every wallpaper.
- Move finished-run cards into a separate History window; keep a single compact active-job status in the queue.
- Update existing queue rows when editing groups, preserving scroll position across large folder queues.
- Save queued drafts automatically and restore them across shell reloads. Keep review/detail dialogs embedded in the manager.

## [1.2.0] - 2026-10-31

- Add the optional Wallpaper Manager reference with mounted-drive places, folder checkboxes, Ctrl/Shift ranges and selections retained across drives.
- Scan several folders together into independent queue batches, each with an explicit group dropdown and its own source path. Handle inaccessible folders independently and de-duplicate overlapping selections.
- Include durable serial background jobs, per-item results, recoverable management and stdin transport for large import queues with visible startup failures.
- Update the native gallery reference and its missing companions; show wallpaper totals in both galleries, with group counts and search scope kept separate.
- Qualify palette imports for Qt 6.12 compatibility. Keep setup home-relative, include decoder attribution and portable tests, and preserve the transition-only installer.

## [1.1.0] - 2026-10-11

- Update integration guide for user-owned plugin clones and correct singleton/shader paths; sanitized sample previews.
- Clean current release files and retire workstation captures. Existing public history is preserved. Future commits use a GitHub noreply address; CI checks current release payloads.
- See docs/RELEASE-PRIVACY.md for scope and limitations. Sample artwork illustrates the design, rather than proving a live runtime result.

All notable changes to `omarchy-theme-transitions` will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-09-08

### Added
- Initial clean public release for Omarchy 4.0.2 / Arch Linux.
- 8 signature transition modes executed on WlrLayer.Background.
- GLSL 440 fragment shader (`transition.frag`) with single-cycle GPU math.
- Dedicated CLI utility `omarchy-theme-transition` and Quickshell transition manager.
- Comprehensive safe user installer script (`install.sh`) supporting `--dry-run`.
- Full security exclusions, sanitized configurations, and complete documentation.
