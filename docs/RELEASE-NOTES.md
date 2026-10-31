# omarchy-theme-transitions 1.3.0

Retry failed wallpaper imports directly from **History**, with their original folder and group choices.

Choose **Retry failed…**, review the remaining files, then confirm. The new background job includes only failed or unfinished items. Successful imports and recovered files remain untouched, including identical sources moved to a different drive. Names, groups, desktop targets and media options are preserved.

Separate draft queues and original history remain intact. The manager prevents overlapping retries for the same family of runs and reports when everything has already recovered. Retry controls become available after a run finishes; interrupted runs can retry their unfinished items.

## Added and improved

- **Mounted-drive browsing:** Home, File system and mounted data drives appear in Places. Read-only sources are supported; Refresh drives updates the list.
- **Multi-folder selection:** Checkboxes, Ctrl/Shift ranges and Ctrl+A work in folder mode. Selections remain while browsing other folders or drives, with a removable list of chosen paths. Opening a folder does not select it for scanning.
- **Separate folder batches:** One scan creates independent queue entries. Each has its own group dropdown and full source path; new groups can be reused across batches. Empty, missing or unreadable folders report issues independently, and overlapping selections are de-duplicated. Recursion stays opt-in.
- **Background imports:** Durable serial jobs continue after the manager closes. Large requests stream over stdin, and failed helper launches show an error while retaining the queue. Per-item results, explicit grouping and recoverable management are included.
- **Accessible history on empty queue:** History is located on the common Add toolbar, keeping job details and retry reachable directly from Prepare batch with zero queued items.
- **Gallery totals:** Both native galleries display wallpaper totals; group count and search scope remain separate. The gallery reference now includes its model, listing helper and sample manifest.
- **Current Qt compatibility:** Explicit palette imports preserve the intended colors with Qt 6.12, and the embedded chooser keeps controls within the manager.
- **Import preflight:** Configured backup destinations are checked before accepting a job, so one setup problem is reported before image processing. The draft remains available for retry.
- **Stable queue workspace:** Finished runs move to History, and group edits update an existing row without scrolling the queue back to the top. Only a compact active-job status stays in the working area.
- **Draft recovery:** Queued folders and their settings save automatically and return after a shell reload. Review and detail dialogs stay embedded in the manager.

## Setup

The existing `./install.sh install` command continues to install the transition CLI. The manager is an optional user-owned reference integration with its own [setup guide](../reference/wallpaper-manager/README.md). Review that guide before copying the manager, picker or helper files. No new theme, wallpaper, keybinding or transition mode is applied by this release.

The manager reference includes Python source, its QML/JS components, decoder attribution and portable regression tests. The public GUI defaults to Omarchy; alternate-desktop destinations remain explicit choices. Runtime data and workstation files are excluded from the release payload.

## Validation

- 120 portable backend/reference tests passed locally, including failed-only selection, preserved options/drafts, recovered and moved-source detection, interrupted jobs and duplicate retry prevention.
- Sixteen GUI interaction cases passed at normal and smaller sizes, including zero-queue History/Details/Retry accessibility, retry-button visibility/dispatch, a 40-batch scroll-retention check and a 20-run history layout check, plus the earlier real mounted-drive open/selection check.
- The installed manager displayed the mounted drive, and existing registry entries, group assignments and the active theme remained unchanged during this update.
- Current payload privacy checks and shell syntax checks passed. CI runs the portable backend suite; Quickshell/Wayland checks skip when their runtime is unavailable.

These checks cover the manager and picker update. They do not repeat every GPU transition-mode benchmark.
