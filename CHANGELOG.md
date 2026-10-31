# Changelog

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
