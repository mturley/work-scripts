# work-scripts

Personal CLI tools for git worktree workflows.

## Compatibility

Scripts must be compatible with the built-in versions of tools that ship with macOS, including:

- **bash 3** (macOS ships bash 3.2, not bash 4+). Avoid `mapfile`, `readarray`, associative arrays (`declare -A`), and other bash 4+ features.
- **find**, **sed**, **awk**, **grep** — use POSIX-compatible options. Avoid GNU-specific flags.
