# cmux-code

Open VS Code in the current directory, then close the cmux tab it ran in.

## Background

cmux (the terminal multiplexer app) runs command-action hotkeys in a **new tab
(surface)** rather than in the current one. If you bind a hotkey to `code .`, you
get a throwaway tab that just sits there after VS Code opens. This script opens
`code` and then closes that tab automatically, so the hotkey feels like a single
"open in VS Code" action with no leftover terminal.

The tab-closing trick is `cmux close-surface`, which defaults to the calling
surface via the `CMUX_SURFACE_ID` and `CMUX_WORKSPACE_ID` environment variables
that cmux sets in every surface. (Same mechanism as `handler switch
--close-caller` in the agent-ledger project, reimplemented in bash.)

## Prerequisites

- `code` — the VS Code CLI (enable via VS Code: Command Palette → "Shell Command: Install 'code' command in PATH")
- `cmux` — the cmux CLI, and the script must run inside a cmux surface

## Usage

```bash
# Open VS Code in the current directory, then close the tab
cmux-code

# Open a specific path
cmux-code ~/git/some-project
```

### Binding to a cmux hotkey

Add a command action in your cmux config that runs `cmux-code` in the current
directory. cmux opens it in a new tab; `cmux-code` opens VS Code and closes that
tab immediately.

## Behavior on failure

The tab is only closed on success:

- If `code` is not on PATH, or `code` exits non-zero, the tab stays open so you
  can see the error.
- If not running inside cmux (no `CMUX_SURFACE_ID`), or `cmux` is not on PATH,
  the script opens VS Code and leaves the shell alone.
