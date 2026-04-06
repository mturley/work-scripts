# gh-safe

A safety wrapper for the GitHub CLI. Read-only operations pass through immediately; write operations require explicit approval via `APPROVE=true`.

```bash
gh-safe pr list                    # passes through (read-only)
gh-safe pr merge 123               # blocked (write operation)
APPROVE=true gh-safe pr merge 123  # allowed
```

Useful as a drop-in replacement for `gh` in automated contexts (e.g. Claude Code hooks) where you want to prevent accidental writes.

## Claude Code integration

Add something like this to your `AGENTS.md` or `CLAUDE.md`:

```markdown
# GitHub Operations

- **CRITICAL: `gh-safe` replaces `gh` (GitHub CLI), NOT `git`.** Use `git` directly for all git operations (`git push`, `git commit`, etc.). Use `gh-safe` anywhere you would use the `gh` command. NEVER use `gh` directly — ALWAYS use `gh-safe` instead.
- **Never decide for yourself whether a `gh` operation is safe.** The `gh-safe` wrapper (available on PATH) makes that determination. If the command is read-only, it runs immediately. If not, it exits with code 2 and prints "command not read-only. approval required."
- **`gh-safe` approval process** (NEVER skip these steps):
  1. Always run `gh-safe ...` first WITHOUT `APPROVE=true` — let `gh-safe` decide whether the command is safe
  2. If it reports "approval required", ask the user for explicit approval
  3. Only after the user approves, re-run with `APPROVE=true gh-safe ...`
```

To benefit most from this script you can also add these to your Claude Code `settings.json` permissions so `gh-safe` commands don't require manual tool approval:

```json
"Bash(gh-safe *)",
"Bash(APPROVE=true gh-safe *)",
```
