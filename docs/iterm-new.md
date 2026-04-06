# iterm-new

Open a new [iTerm2](https://iterm2.com/) tab or split pane and run a command. The tab/pane is named after the command or a custom name.

```bash
iterm-new tab npm run dev            # new tab
iterm-new split-v npm run dev        # vertical split
iterm-new split-h npm run dev        # horizontal split
iterm-new tab -n "my app" npm start  # new tab with custom name
```

## Modes

| Mode | Description |
|------|-------------|
| `tab` | Open a new tab |
| `split-v` | Split vertically |
| `split-h` | Split horizontally |

## Options

| Flag | Description |
|------|-------------|
| `-n <name>` | Name the tab/pane (defaults to the command) |

## Behavior

1. Opens a new tab or split pane in the current iTerm2 window
2. Names it (custom name via `-n`, or the command itself)
3. `cd`s to the caller's working directory
4. Runs the command

The command exits immediately, so to open multiple tabs/panes you can chain multiple calls with `&&` or `;`.

## Setup

Requires [iTerm2](https://iterm2.com/). No additional configuration needed.
