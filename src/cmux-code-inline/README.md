# cmux-code-inline

Open the current directory in cmux's **inline** VS Code by reusing an
already-running cmux-managed VS Code web server.

## Background

cmux has a built-in command palette action, **"Open Current Directory in VS Code
(inline)"**, that starts a VS Code [`serve-web`](https://code.visualstudio.com/docs/remote/vscode-server)
server (bound to `127.0.0.1` on a random port, with a per-server connection
token) and opens it inside a cmux browser surface. This is different from
[`cmux-code`](../cmux-code/), which shells out to the external `code` app.

That built-in action is **not** exposed as a bindable shortcut or a `cmux` CLI
command — you can only trigger it from the command palette. This script works
around that.

It does **not** start the server. Instead it:

1. Finds an already-running cmux-managed `serve-web` process (identified by the
   `cmux-vscode-token-*` connection-token file cmux passes it).
2. Reads that server's connection token and discovers its listening port via
   `lsof`.
3. Opens `http://127.0.0.1:<port>/?tkn=<token>&folder=<PATH>` in a new cmux
   browser surface.
4. Closes the throwaway tab it was launched from (like [`cmux-code`](../cmux-code/)),
   so the hotkey feels like a single action with no leftover terminal.

The server stays alive as long as cmux keeps it running, so after starting it
**once** via the palette, this script can reopen the inline editor at any folder
without touching the palette again.

## Prerequisites

- `cmux` — the cmux CLI, and the script must run inside a cmux surface
- A running cmux VS Code server. Start one once via the cmux command palette:
  Cmd+Shift+P → "Open Current Directory in VS Code (inline)".

## Usage

```bash
# Open the current directory in inline VS Code
cmux-code-inline

# Open a specific path
cmux-code-inline ~/git/some-project
```

### Binding to a cmux hotkey

Add a command action in your cmux config (`~/.config/cmux/cmux.json`) that runs
`cmux-code-inline`. cmux opens command actions in a new tab; this script opens
the inline editor in its own browser surface.

```jsonc
"actions": {
  "cmux-code-inline": {
    "type": "command",
    "command": "cmux-code-inline",
    "title": "Open in VS Code (inline)",
    "subtitle": "Reopen this directory in cmux's inline VS Code server",
    "shortcut": "cmd+shift+c",
    "palette": true
  }
}
```

## Behavior on failure

- If no running cmux VS Code server is found, the script aborts (without opening
  a surface or closing its tab) and tells you to run the palette action once to
  start one, then retry.
- If `cmux` is not on PATH, or the given path is not a directory, it aborts with
  an explanatory message.
- The launch tab is only closed *after* the inline editor surface opens, and only
  when running inside a cmux surface (`CMUX_SURFACE_ID` set). Any error before
  that point leaves the tab open so you can see it.
