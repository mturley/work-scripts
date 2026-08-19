# cmux-open-next-pane

Open a file or URL in the cmux pane *after* the current one, collecting opened
files there instead of scattering them into new splits. If the current pane is
the last pane, create one clean new split instead.

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

- **Focused pane is not the last pane** — the target opens as a new tab in the
  next pane:

  ```
  cmux open <target> --pane <next-pane> --no-focus
  ```

  This is uniform across markdown files, other files, and URLs. Markdown files
  keep their rich live-reload viewer.

- **Focused pane is the last pane** — a new split is created. The command is
  chosen by target type so the split is clean (no stray terminal tab):

  | Target      | Command                                    | Result              |
  |-------------|--------------------------------------------|---------------------|
  | `*.md`      | `cmux markdown open <target> --focus false`| clean split, viewer |
  | URL         | `cmux open <target> --no-focus`            | clean browser split |
  | other file  | `cmux open <target> --no-focus`            | tab in current pane |

  (For arbitrary non-markdown files there is no cmux primitive that splits
  without leaving a stray empty terminal tab, so those fall back to a tab.)

In every case the target opens without stealing focus.

## Prerequisites

- `cmux` — the cmux CLI, and the script must run inside a cmux workspace
  (`CMUX_WORKSPACE_ID` must be set, which cmux sets in every surface)

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
