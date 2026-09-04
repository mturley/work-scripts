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

### Options

| Option | Description |
| --- | --- |
| `--bind ADDR` | Host/IP for `worktree ui` to bind. Default `127.0.0.1` (this machine only). |
| `--yes` | Forwarded to `worktree ui` to skip its confirmation prompt. The warning is still printed. |

## Reaching the worktree UI from another device

By default both UIs bind to loopback, so they are reachable only from this
machine. To use the worktree UI from your phone or another computer on the LAN:

```bash
cmux-tool-servers --bind 0.0.0.0
```

Then browse to `http://<this-mac's-LAN-IP>:8475` from the other device. On macOS
the application firewall will prompt once to allow incoming connections for the
`worktree` binary.

**Read the warning before you do this.** The worktree UI has **no
authentication** and is not read-only — anyone who can reach the port can create
and delete worktrees, run cmux commands, and read your Slack threads through its
proxy endpoints, which use your Slack session credentials for any caller. Only
do it on a network you trust; for access from outside the LAN, prefer a VPN such
as Tailscale over exposing the port.

By default `worktree ui` prints that warning and asks `Continue? [y/N]` **in its
mprocs pane** — mprocs gives each pane a pty, so it can prompt there. To reach
the prompt, select the `worktree` process and press `Ctrl-a` to focus its
terminal, then answer.

The prompt reappears **after every supervisor restart**, since each restart is a
fresh bind. Once you have decided, `--yes` skips it:

```bash
cmux-tool-servers --bind 0.0.0.0 --yes
```

`--yes` is forwarded to `worktree ui` only when you pass it explicitly — the
script never adds it on your behalf. The warning is still printed either way;
`--yes` suppresses the question, not the notice.

Two more things worth knowing:

- **`--bind` applies to `worktree ui` only.** `handler ui` is not affected and
  stays bound to loopback.
- Without `--yes`, answering `n` does not end the session — the supervisor
  relaunches in 5 seconds and asks again. Quit mprocs to stop.

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
  `cmux-tool-servers --supervise handler ui --no-open` and
  `cmux-tool-servers --supervise worktree ui --no-open`. (`--no-open` keeps
  each UI from opening a browser tab on launch — useful when they restart.)
- The restart delay is 5 seconds (`RESTART_DELAY` in the script).

## Behavior on failure

- If `mprocs`, `handler`, or `worktree` is missing from PATH, the script prints
  which tool(s) are missing and exits non-zero before launching anything.
- Any unrecognized argument prints usage and exits non-zero.
