# cmux-open-next-pane

Open a file or URL in the cmux pane *after* the current one, collecting opened
files there instead of scattering them into new splits. If the file is already
open in the workspace, don't open a duplicate — switch to the existing tab when
this workspace is focused, or do nothing when it's in the background. If the
current pane is the last pane, create one clean new split instead.

## Background

cmux's `markdown open` (and browser opens) **always create a new split**. If you
open several markdown files or PR/Jira URLs in a row, you end up with a row of
tiny splits instead of a single review pane. This script collects opened targets
into the pane immediately to the right of the focused one, only splitting when
there is nothing to the right.

In cmux terminology, a **pane** is a split (a layout region) and a **surface** is
a tab within a pane. `cmux list-panes` lists panes in layout order and marks the
focused one, so the script can find the pane that follows the current one.

### Behavior

- **Already open** — before opening anything, the script checks whether a file
  surface in the current workspace is already showing this file (matched by
  **basename**, since cmux only exposes the basename, not the full path). If so,
  it never opens a duplicate. What it does then depends on whether this
  workspace is the one currently in focus:
  - **This workspace is focused** (its window is the frontmost/key window *and*
    this workspace is that window's selected workspace) — it switches the pane to
    the existing tab, then restores focus to the pane it started from. The tab is
    surfaced without leaving your focused pane changed.
  - **Running in a background workspace** — it does nothing at all. This is
    deliberate: a file written by a background agent should never pull your focus
    over to its workspace.

  This step is skipped for URLs (their titles are hostnames) and when `jq` is not
  installed. It also keeps repeated opens (e.g. an editor hook firing on every
  save) from piling up duplicate tabs.

- **Focused pane is not the last pane** — the target opens as a new tab in the
  next pane:

  ```
  cmux open <target> --pane <next-pane> --no-focus
  ```

  This is uniform across markdown files, other files, and URLs. Markdown files
  keep their rich live-reload viewer.

- **Focused pane is the last pane** — a new split is created. The command is
  chosen by target type so the split is clean (no stray terminal tab):

  | Target      | Command                                     | Result              |
  |-------------|---------------------------------------------|---------------------|
  | `*.md`      | `cmux markdown open <target> --focus false` | clean split, viewer |
  | URL         | `cmux open <target> --no-focus`             | clean browser split |
  | other file  | `cmux open <target> --no-focus`             | tab in current pane |

  (For arbitrary non-markdown files there is no cmux primitive that splits
  without leaving a stray empty terminal tab, so those fall back to a tab.)

In every case the target opens without stealing focus.

## Prerequisites

- `cmux` — the cmux CLI, and the script must run inside a cmux workspace
  (`CMUX_WORKSPACE_ID` must be set, which cmux sets in every surface)
- `jq` — optional; used only for the "already open" check. Without it, that
  step is skipped and the file opens normally.

## Usage

```bash
# Open a markdown file in the next pane (or a clean split if you're last)
cmux-open-next-pane ~/tmp/design.md

# Open a PR or Jira URL alongside your work
cmux-open-next-pane https://github.com/opendatahub-io/odh-dashboard/pull/1234

# Forward extra flags to the underlying cmux command
cmux-open-next-pane ~/notes.md --workspace workspace:2
```

## Behavior on failure

- If `cmux` is not on PATH, the script errors and exits non-zero.
- If not running inside cmux (`CMUX_WORKSPACE_ID` unset), the script errors and
  exits non-zero rather than opening anything.
- If no argument is given, it prints usage and exits non-zero.
