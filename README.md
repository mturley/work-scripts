# work-scripts

Personal CLI tools for git and GitHub workflows.

- [`worktree`](#worktree) — Create and manage git worktrees for PRs and branches, with optional symlinked dependencies
- [`gh-safe`](#gh-safe) — Safety wrapper for agents using GitHub CLI that skips manual approval for read-only operations but blocks write operations unless approved

## Setup

- Install prerequisites: [GitHub CLI](https://cli.github.com/) (`gh`, must be authenticated) and Python 3
- Clone the repo:
  ```bash
  git clone git@github.com:mturley/work-scripts.git ~/git/work-scripts
  ```
- Add the `bin` subdirectory to your PATH (e.g. in `~/.zshrc`):
  ```bash
  export PATH=$HOME/git/work-scripts/bin:$PATH
  ```
- Optionally, set `WORKTREES_BASE` to control where worktrees are created (default: `~/git/.worktrees`). This should be outside your project git clones.
  ```bash
  export WORKTREES_BASE=$HOME/git/.worktrees
  ```
- If using `gh-safe` with Claude Code, see the [integration instructions](#gh-safe) below for `CLAUDE.md` and `settings.json` changes.

## Commands

### `worktree`

Unified command for creating and managing git worktrees that optionally share installed dependencies. Accepts a PR number, PR URL, branch name, or worktree path.

Run `worktree` in multiple terminals to open editors in multiple branches at the same time! This is my preferred way to review multiple PRs in parallel: I use the `/review` skill from my [claude-skills](https://github.com/mturley/claude-skills) repo in each worktree's editor. It is also useful for using agents to work on multiple features/bugs in parallel.

```bash
worktree                             # list existing worktrees and select one
worktree 1234                        # create or reopen a worktree for PR #1234
worktree https://github.com/org/repo/pull/1234
worktree my-feature-branch           # create or reopen a branch worktree
worktree ~/git/.worktrees/repo--name # open an existing worktree by path
```

Based on the arguments, the script detects what you're trying to do, finds or creates the relevant worktree, then drops you into an interactive REPL (see below) to manage it.

* **No arguments** — lists all worktrees under `$WORKTREES_BASE`, detects and marks orphaned ones (`.git` missing but files not fully cleaned up), and lets you select one to manage or clean up.

* **PR number or GitHub URL** — fetches the PR, creates a review worktree, and sets up branch tracking against the PR author's remote. If the worktree already exists: offers to reuse, update to latest, or recreate from scratch. Automatically locates the matching local clone if run from a different directory.

* **Branch name** — creates a new branch from `upstream/main` (or `origin/main`) in a worktree. If the branch is already checked out elsewhere, offers to reuse or move it. Asks you which repo to use if run from outside a repo.

* **Worktree path** - if it matches an existing worktree, drops you directly into the REPL to manage it.

After creating a new worktree, the command offers to **symlink** gitignored files from the main clone (node_modules, build outputs, dotfile config) so you can run your dev environment in the worktree without setting things up again if you don't need different dependency versions in the worktree. If you do, you can decline this and install things yourself. It lets you choose which files you want to link and offers to reuse your choice from the last usage in that repo (cached in `/tmp`).

It then **detects your editor** (VS Code or Cursor) or uses a cached preference (in `/tmp`), opens an editor window (or focuses an existing one), and drops into the interactive REPL.

**Interactive REPL** — all paths above end here. Available commands:
- `open` / `o` — open in your editor (focuses the editor window if already open)
- `status` / `s` — run `git status`
- `cleanup` / `c` — remove the worktree and its branch
- `exit` / `e` — quit

I leave the REPL open in multiple terminals for quick cleanup of each one, but you can also exit it and run `worktree` again to get back to it.

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

