# `code-windows`

Fuzzy-find and focus an open VS Code window. Also available as `cw`.

## Usage

```bash
code-windows    # or just: cw
```

Launches an [fzf](https://github.com/junegunn/fzf) picker listing all open VS Code windows by title. Select one to bring it to the front.

## Prerequisites

- **macOS** — uses AppleScript to enumerate and focus windows.
- **[fzf](https://github.com/junegunn/fzf)** — `brew install fzf`
- **Accessibility permissions** — your terminal app (Terminal, iTerm2, etc.) must be allowed in System Settings > Privacy & Security > Accessibility. The script will tell you if this is missing.
