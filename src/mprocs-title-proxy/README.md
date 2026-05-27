# mprocs-title-proxy

A PTY proxy that intercepts terminal title escape sequences (OSC 0/2) and renames the corresponding mprocs pane.

## Usage

```bash
mprocs-title-proxy <command> [args...]
```

Requires `MPROCS_SOCKET` or `WORKTREE_SHELL_MPROCS_SOCK` to be set. Falls back to running the command directly if neither is available.

## How it works

1. Forks the command inside a pseudo-terminal (PTY)
2. Relays all I/O transparently between stdin/stdout and the child PTY
3. Watches the output stream for OSC escape sequences (`\033]0;TITLE\007` or `\033]2;TITLE\007`)
4. When a title change is detected, calls `mprocs --server ... --ctl '{c: rename-proc, name: "TITLE"}'`

The command runs with full terminal capabilities — interactive TUIs, colors, cursor movement, and resize events all work normally.

## Examples

```bash
# Inside an mprocs session with MPROCS_SOCKET set:
mprocs-title-proxy claude    # Claude Code title updates rename the pane
mprocs-title-proxy vim       # vim title updates rename the pane
mprocs-title-proxy htop      # any program that sets terminal title

# Without MPROCS_SOCKET, runs the command directly (no-op wrapper):
mprocs-title-proxy claude    # equivalent to just running 'claude'
```

## Integration

The worktree REPL's `[c]laude` command automatically wraps `claude` with this proxy when running inside an mprocs session.
