# `cmux-tool-servers` — Run the handler & worktree UIs together

Launches [`handler ui`](https://github.com/mturley/agent-handler) and
[`worktree ui`](https://github.com/mturley/worktree) side by side as two panes in
[mprocs](https://github.com/pvolok/mprocs), each in a self-restarting supervisor
so you can swap in freshly built binaries without quitting mprocs.

Both tools expose their full feature set only when run inside cmux — hence the
`cmux` prefix on this script's name.

## Prerequisites

- `mprocs` — the multi-process TUI (`brew install mprocs`)
- `handler` — the [agent-handler](https://github.com/mturley/agent-handler) CLI, on PATH
- `worktree` — the [worktree](https://github.com/mturley/worktree) CLI, on PATH
- Best run inside a cmux workspace, so both UIs get their full feature set.

## Usage

```bash
cmux-tool-servers
```

This opens an mprocs session with two named processes, `handler` and `worktree`,
running `handler ui` and `worktree ui` respectively. Quit mprocs (or Ctrl-C) to
stop both.

## Reinstall-without-quitting workflow

When you're hacking on the handler or worktree projects themselves, you often
want to install a fresh binary — but the old one has to be killed first, and a
plain mprocs pane would just sit there dead once you do.

Each pane here runs its command through a supervisor loop instead: when the child
process exits for **any** reason (you kill it, it crashes, it exits cleanly), the
supervisor waits **5 seconds** and relaunches it. So the workflow is:

1. Kill the running `handler` (or `worktree`) process — e.g. from another shell,
   or by killing the child from within the pane.
2. Install the new binary (`go install …`, etc.).
3. Within 5 seconds the pane relaunches automatically on the new binary.

No need to quit and restart mprocs. When you actually want to stop, quit mprocs.

## Implementation notes

- The supervisor is this same script re-invoked in a hidden `--supervise <cmd>`
  mode, so there's only one file to maintain. mprocs runs
  `cmux-tool-servers --supervise handler ui` and
  `cmux-tool-servers --supervise worktree ui`.
- The restart delay is 5 seconds (`RESTART_DELAY` in the script).

## Behavior on failure

- If `mprocs`, `handler`, or `worktree` is missing from PATH, the script prints
  which tool(s) are missing and exits non-zero before launching anything.
- Any unrecognized argument prints usage and exits non-zero.
