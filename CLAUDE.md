# work-scripts

Personal CLI tools for git worktree workflows.

## Documentation

When creating or modifying scripts in `bin/`, also create or update:
- **`docs/<script-name>.md`** — detailed documentation for the script (prerequisites, usage, examples). Follow the format of existing docs files.
- **`README.md`** — add or update the script's entry with a short description and usage examples. Place it under the appropriate section heading.

## Compatibility

Scripts must be compatible with the built-in versions of tools that ship with macOS, including:

- **bash 3** (macOS ships bash 3.2, not bash 4+). Avoid `mapfile`, `readarray`, associative arrays (`declare -A`), and other bash 4+ features.
- **find**, **sed**, **awk**, **grep** — use POSIX-compatible options. Avoid GNU-specific flags.
