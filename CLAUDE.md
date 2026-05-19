# work-scripts

Personal CLI tools for git worktree workflows.

## Structure

Each script lives in `src/<script-name>/` alongside its documentation:
- **`src/<script-name>/<script-name>`** — the script itself
- **`src/<script-name>/README.md`** — detailed documentation (prerequisites, usage, examples)

The `bin/` directory contains symlinks pointing to the scripts in `src/`.

## Documentation

When creating or modifying scripts, also create or update:
- **`src/<script-name>/README.md`** — detailed documentation for the script (prerequisites, usage, examples). Follow the format of existing README files.
- **`README.md`** — add or update the script's entry with a short description and usage examples. Place it under the appropriate section heading. Links to docs should point to `src/<script-name>/` (GitHub renders README.md automatically).

## Compatibility

Scripts must be compatible with the built-in versions of tools that ship with macOS, including:

- **bash 3** (macOS ships bash 3.2, not bash 4+). Avoid `mapfile`, `readarray`, associative arrays (`declare -A`), and other bash 4+ features.
- **find**, **sed**, **awk**, **grep** — use POSIX-compatible options. Avoid GNU-specific flags.