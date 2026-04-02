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

Unified entry point for managing git worktrees. Accepts a PR number, PR URL, branch name, or worktree path.

```bash
worktree <pr-number|pr-url|branch-name|worktree-path>
```

If a worktree already exists for the given argument, opens an interactive REPL with commands to open, check status, or clean up the worktree. Otherwise delegates to `pr-worktree` or `branch-worktree` to create one.

### `branch-worktree`

Creates an isolated git worktree for a new branch (based on `upstream/main`) and opens it in a new editor window.

```bash
branch-worktree <branch-name>
```

Can be run from within a git repository or from a workspace directory containing multiple repos (will prompt to select one). If the branch already exists, reuses it as-is.

### `pr-worktree`

Creates an isolated git worktree for a pull request and opens it in a new editor window.

```bash
pr-worktree <pr-number|branch|url>
```

Accepts a PR number (when run from the correct repo), or a full GitHub PR URL (will search `~/` for a local clone). If a worktree already exists for the PR, offers to reuse, update, or recreate it.

### `gh-safe`

A safety wrapper for the GitHub CLI. Read-only operations pass through immediately; write operations require explicit approval via `APPROVE=true`.

```bash
gh-safe pr list                    # passes through (read-only)
gh-safe pr merge 123               # blocked (write operation)
APPROVE=true gh-safe pr merge 123  # allowed
```

Useful as a drop-in replacement for `gh` in automated contexts (e.g. Claude Code hooks) where you want to prevent accidental writes.

## Configuration

Set `WORKTREES_BASE` to control where worktrees are created (default: `~/git/.worktrees`):

```bash
export WORKTREES_BASE=$HOME/git/.worktrees
```

## Worktree details

Both worktree commands:

1. If run from a workspace containing nested git repos, prompt to select a project repo
2. Create a worktree in `$WORKTREES_BASE` (default `~/git/.worktrees/`)
3. If the branch is already checked out in another worktree, offer to reuse or move it
4. Offer to copy useful files (node_modules, build outputs, dotfile config) from the main worktree
5. Detect your editor (VS Code, Cursor) and open a new window
6. Detect the project's dependency manager and show install instructions

### Cleanup

Use `worktree <arg>` to open the REPL for an existing worktree, then use the `cleanup` command. Or remove directly:

```bash
git worktree remove ~/git/.worktrees/<name>
git worktree list
```
