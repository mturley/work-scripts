# work-scripts

Personal CLI tools for git and GitHub workflows.

## Setup

```bash
git clone git@github.com:mturley/work-scripts.git ~/git/work-scripts
```

Add to your PATH (e.g. in `~/.zshrc`):

```bash
export PATH=$HOME/git/work-scripts/bin:$PATH
```

### Prerequisites

- [GitHub CLI](https://cli.github.com/) (`gh`) must be installed and authenticated
- Python 3 (for JSON parsing)

## Commands

### `worktree`

Unified command for creating and managing git worktrees. Accepts a PR number, PR URL, branch name, or worktree path.

```bash
worktree                             # list existing worktrees and select one
worktree 1234                        # open or create a worktree for PR #1234
worktree https://github.com/org/repo/pull/1234
worktree my-feature-branch           # create a branch worktree from upstream/main
worktree ~/git/.worktrees/repo--name # open an existing worktree by path
```

**No arguments** — lists all worktrees under `$WORKTREES_BASE`, marks orphaned ones, and lets you select one to manage or clean up.

**Existing worktree** — if a worktree already exists for the argument, opens an interactive REPL with commands:
- `open` / `o` — open in your editor
- `status` / `s` — run `git status`
- `cleanup` / `c` — remove the worktree and its branch
- `exit` / `e` — quit

**New PR worktree** (number or GitHub URL) — fetches the PR, creates a review worktree, and sets up branch tracking against the PR author's remote. If the worktree already exists, offers to reuse, update to latest, or recreate from scratch. Automatically locates the matching local clone if run from a different directory.

**New branch worktree** — creates a new branch from `upstream/main` (or `origin/main`) in a worktree. If the branch is already checked out elsewhere, offers to reuse or move it.

After creating a worktree, the command:
1. Offers to **symlink** files from the main clone (node_modules, build outputs, dotfile config) — these are shared via symlink, so dependency changes affect both
2. **Detects your editor** (VS Code or Cursor) or uses a cached preference, and opens a new window
3. Drops into the **interactive REPL** for further management

### `gh-safe`

A safety wrapper for the GitHub CLI. Read-only operations pass through immediately; write operations require explicit approval via `APPROVE=true`.

```bash
gh-safe pr list                    # passes through (read-only)
gh-safe pr merge 123               # blocked (write operation)
APPROVE=true gh-safe pr merge 123  # allowed
```

Useful as a drop-in replacement for `gh` in automated contexts (e.g. Claude Code hooks) where you want to prevent accidental writes.

To integrate with Claude Code, add something like this to your `AGENTS.md` or `CLAUDE.md`:

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

## Configuration

Set `WORKTREES_BASE` to control where worktrees are created (default: `~/git/.worktrees`):

```bash
export WORKTREES_BASE=$HOME/git/.worktrees
```

### Cleanup

Use `worktree <arg>` to open the REPL for an existing worktree, then use the `cleanup` command. Or remove directly:

```bash
git worktree remove ~/git/.worktrees/<name>
git worktree list
```
