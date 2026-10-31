# Wallpaper Manager reference

This optional user-owned Quickshell manager extends the theme picker with mounted-drive browsing, explicit groups and independent background import batches. It is a companion reference implementation; the repository's transition CLI installer remains unchanged.

## Workflow

1. Open **Add wallpapers → Scan folders…**.
2. Use **Places** to open Home, the file system or a mounted drive. **Refresh drives** picks up new mounts. Read-only sources can be selected; the manager only reads source files.
3. Check several folders, use Ctrl/Shift-click or Ctrl+A, and browse to another folder or drive to keep selecting. **Open** or double-click browses without selecting a folder. **Add current folder** includes the folder being viewed. The selected-folder list lets you remove individual choices.
4. Choose **Scan N folders**. Each selected folder becomes its own queue batch. Scans are shallow unless **Include subfolders** is enabled. Overlapping selections are de-duplicated; the most specific selected folder owns its sources. Missing or inaccessible folders report issues independently.
5. In **Queue**, choose an existing group or type a new group for each folder. New group names are reusable across batches. Blank means ungrouped. Folder names and full paths distinguish identically named folders on different drives. Reorder or remove batches as needed.
6. Choose **Start in background…** and confirm. Requests stream over stdin, supporting queues larger than the operating system's command-line argument limit. A failed helper launch reports an error and retains the queue. Submitted jobs keep running after the manager closes and report completion in a notification.

Scanning does not install wallpapers, assign existing themes to groups, or change the active wallpaper. The library retains explicit grouping, display names, group covers, multi-selection and recoverable removal. File selection still supports per-wallpaper names and explicit recovered-asset selection before queuing.

Queue drafts save automatically in `data/pending-draft.json` and restore after shell reloads. Submitted requests and progress are durable in `data/jobs/`; installation recovery is in `data/backups/`. Source originals are preserved. Reusing an already installed theme name requires an explicit replace choice and retains recovery files.

Only one compact active-job status appears below the queue. Previous runs stay in the separate **History** window with their own **Details**, so repeated runs cannot crowd out folder controls. Editing a group updates its existing row and preserves the current scroll position. Configured backup destinations are checked before job acceptance; a missing destination causes one setup error before image processing and keeps the draft for retry.

## Requirements

- An Omarchy shell with user-owned overlay plugins, Quickshell and Qt Quick Controls. The updated chooser was checked with Omarchy 4.0.6 and Qt 6.12.
- Python 3.11+ and Pillow (`python-pillow` on Arch).
- Aether for generating theme colors. The backend invokes only its palette export with `--no-apply`.
- FFmpeg/ffprobe for video inspection, posters and optional still recovery. Live video playback also requires an existing compatible live-wallpaper integration; this reference does not install a player.

Workshop folders and PKG/TEX data use the included decoder with its separate MIT license and attribution in `vendor/`. Projects are read as data; their scripts/shaders are not executed. Numeric Workshop IDs use the standard Steam Workshop content directory as their default lookup location; explicit selected folders work from any mounted drive.

## Manual integration

Review and back up an existing manager before updating it. Keep its `data/` directory, registry and installed themes together. The reference does not include workstation configuration, wallpapers, credentials or runtime receipts.

1. Place this directory's Python modules, `vendor/` and `integration/` under `~/Projects/wallpaper-importer/`. The GUI and group-picker helpers use this documented home-relative backend location.
2. Copy `integration/wallpaper-manager/` to `~/.config/omarchy/plugins/daemon0.wallpaper-manager/`. Preserve the module's `manifest.json` and all companion QML/JS files. The stable plugin ID is intentional integration provenance.
3. Add `{ "id": "daemon0.wallpaper-manager" }` to the existing `plugins` array in `~/.config/omarchy/shell.json`, retaining its other entries. Reload the shell through its normal supported route after saving any draft selections.
4. Make `wallpaper_manager.py` executable and expose it as `~/.local/bin/wallpaper-manager`, or launch it with `python3 ~/Projects/wallpaper-importer/wallpaper_manager.py --gui`.
5. Optionally bind an unused shortcut such as Super+Ctrl+M to `wallpaper-manager`. The caption describes that suggested binding; the reference does not modify keybindings automatically.

The public GUI defaults to Omarchy. Optional alternate-desktop targets remain explicit choices for systems with the corresponding integration installed. Standalone installs retain transactional recovery journals. Systems already providing both DaemonOS backup manifests can use the existing backup coverage validation; register the chosen source location in that backup configuration before importing.

## Gallery and grouped selectors

The repository's `reference/ImagePicker.qml`, `ImagePickerModel.js` and `list.sh` form the updated native card-gallery reference. Install them together in a user-owned image-picker clone. Its companion `image-picker.manifest.json` shows the expected overlay entry point; preserve the clone's identity when integrating it. The sample uses the stable `daemon0.image-picker` clone ID and its home-relative helper directory. When adapting a different clone ID, update `scriptPath()` to that clone's directory as part of the port.

Optional launchers in `integration/` provide group covers and themes within the active group. Review their integration with an existing theme picker before placing them in `~/.local/bin/`. They share `theme-groups.json`, `theme-names.json` and the installed wallpaper registry. Theme Gallery reports the wallpaper total across groups; Wallpaper Gallery counts its available background entries. Group count and search scope remain separate.

## Verification

From the repository root:

```sh
PYTHONPATH=reference/wallpaper-manager python3 -m unittest discover \
  -s reference/wallpaper-manager/tests -p 'test_*.py'
python3 tools/release_privacy_check.py
```

Tests use disposable homes and mock activation. Quickshell transport checks run when Quickshell is available; the full workspace wiring check also requires an active Wayland session and opens no visible test window. Tests cover mounted-place decoding, read-only locations, per-folder scans, optional recursion, overlapping selections, explicit groups, detached jobs, large requests and helper failures.

The source GUI additionally passed twelve interaction cases at normal and smaller sizes, plus a real mounted-drive selection check. This validates the manager/picker update; it does not repeat every GPU transition-mode benchmark.
