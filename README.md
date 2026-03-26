# work-scripts

Personal CLI tools for git worktree workflows.

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

## Configuration

Set `WORKTREES_BASE` to control where worktrees are created (default: `~/git/.worktrees`):

```bash
export WORKTREES_BASE=$HOME/git/.worktrees
```

## Commands

### `pr-worktree`

Creates an isolated git worktree for a pull request and opens it in a new editor window.

```bash
pr-worktree <pr-number|branch|url>
```

Accepts a PR number (when run from the correct repo), or a full GitHub PR URL (will search `~/` for a local clone). If a worktree already exists for the PR, offers to reuse, update, or recreate it.

### `branch-worktree`

Creates an isolated git worktree for a new branch and opens it in a new editor window.

```bash
branch-worktree <branch-name>
```

Can be run from within a git repository or from a workspace directory containing multiple repos (will prompt to select one).

## What they do

Both commands:

1. If run from a workspace containing nested git repos, prompt to select a project repo
2. Create a worktree in `$WORKTREES_BASE` (default `~/git/.worktrees/`, e.g. `~/git/.worktrees/odh-dashboard--pr-123-slug`)
3. If the branch is already checked out in another worktree, offer to reuse or move it
4. Offer to copy gitignored files (e.g. `node_modules/`) from the main worktree
5. Detect your editor (VS Code, Cursor) and open a new window
6. Detect the project's dependency manager and show install instructions

## Cleanup

```bash
# Remove a specific worktree (from the project repo)
git worktree remove ~/git/.worktrees/<name>

# List all worktrees
git worktree list
```
