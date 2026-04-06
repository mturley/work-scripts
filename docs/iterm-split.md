# iterm-split

Split the current [iTerm2](https://iterm2.com/) window and run a command in the new pane. The pane is named after the command for easy identification.

```bash
iterm-split npm run dev              # vertical split (default)
iterm-split -v npm run dev           # vertical split (explicit)
iterm-split -h npm run dev           # horizontal split
```

## Options

| Flag | Description |
|------|-------------|
| `-v` | Split vertically (default) |
| `-h` | Split horizontally |

## Behavior

1. Splits the current iTerm2 session in the chosen direction
2. Names the new pane after the command
3. `cd`s to the caller's working directory
4. Runs the command

The command exits immediately, so to open multiple concurrent panes you can chain multiple calls with `&&` or `;`.

## Setup

Requires [iTerm2](https://iterm2.com/). No additional configuration needed.
