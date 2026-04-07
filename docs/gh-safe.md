# gh-safe

A safety wrapper for the GitHub CLI. Read-only operations pass through immediately; write operations require explicit approval via `--approve`.

## Prerequisites

- [GitHub CLI](https://cli.github.com/) (`gh`, must be authenticated)

## Usage

```bash
gh-safe pr list                     # passes through (read-only)
gh-safe pr merge 123                # blocked (write operation)
gh-safe --approve pr merge 123      # allowed
```

Useful as a drop-in replacement for `gh` in automated contexts (e.g. Claude Code hooks) where you want to prevent accidental writes.

## Claude Code integration

Add something like this to your `AGENTS.md` or `CLAUDE.md`:

```markdown
# GitHub Operations

- **CRITICAL: `gh-safe` replaces `gh` (GitHub CLI), NOT `git`.** Use `git` directly for all git operations (`git push`, `git commit`, etc.). Use `gh-safe` anywhere you would use the `gh` command. NEVER use `gh` directly — ALWAYS use `gh-safe` instead.
- **Never decide for yourself whether a `gh` operation is safe.** The `gh-safe` wrapper (available on PATH) makes that determination. If the command is read-only, it runs immediately. If not, it exits with code 2 and prints "command not read-only. approval required."
- **`gh-safe` approval process** (NEVER skip these steps):
  1. Always run `gh-safe ...` first WITHOUT `--approve` — let `gh-safe` decide whether the command is safe
  2. If it reports "approval required", immediately re-run it with `gh-safe --approve ...`, which will prompt the user for approval.
```

Add these lines to your Claude Code `settings.json` permissions so `gh-safe` commands don't require manual tool approval unless being called with `--approve`:

```json
"allow": [
  "Bash(gh-safe *)"
],
"ask": [
  "Bash(gh-safe --approve *)"
]
```
