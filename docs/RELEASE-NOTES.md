# omarchy-theme-transitions 1.2.0

Select wallpaper folders from mounted drives, scan several at once, and assign a separate group to each folder before starting background imports.

## Added and improved

- **Mounted-drive browsing:** Home, File system and mounted data drives appear in Places. Read-only sources are supported; Refresh drives updates the list.
- **Multi-folder selection:** Checkboxes, Ctrl/Shift ranges and Ctrl+A work in folder mode. Selections remain while browsing other folders or drives, with a removable list of chosen paths. Opening a folder does not select it for scanning.
- **Separate folder batches:** One scan creates independent queue entries. Each has its own group dropdown and full source path; new groups can be reused across batches. Empty, missing or unreadable folders report issues independently, and overlapping selections are de-duplicated. Recursion stays opt-in.
- **Background imports:** Durable serial jobs continue after the manager closes. Large requests stream over stdin, and failed helper launches show an error while retaining the queue. Per-item results, explicit grouping and recoverable management are included.
- **Gallery totals:** Both native galleries display wallpaper totals; group count and search scope remain separate. The gallery reference now includes its model, listing helper and sample manifest.
- **Current Qt compatibility:** Explicit palette imports preserve the intended colors with Qt 6.12, and the embedded chooser keeps controls within the manager.

## Setup

The existing `./install.sh install` command continues to install the transition CLI. The manager is an optional user-owned reference integration with its own [setup guide](../reference/wallpaper-manager/README.md). Review that guide before copying the manager, picker or helper files. No new theme, wallpaper, keybinding or transition mode is applied by this release.

The manager reference includes Python source, its QML/JS components, decoder attribution and portable regression tests. The public GUI defaults to Omarchy; alternate-desktop destinations remain explicit choices. Runtime data and workstation files are excluded from the release payload.

## Validation

- 107 portable backend/reference tests passed locally, including a real detached import into a disposable home and full scan-to-queue wiring.
- Twelve GUI interaction cases passed at normal and smaller sizes, plus a real mounted-drive open/selection check.
- The installed manager displayed the mounted drive, and existing registry entries, group assignments and the active theme remained unchanged during this update.
- Current payload privacy checks and shell syntax checks passed. CI runs the portable backend suite; Quickshell/Wayland checks skip when their runtime is unavailable.

These checks cover the manager and picker update. They do not repeat every GPU transition-mode benchmark.
