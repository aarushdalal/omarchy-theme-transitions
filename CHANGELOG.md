# Changelog

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
