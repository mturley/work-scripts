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

Must be run from within a git repository.

## What they do

Both commands:

1. Create a worktree in a `.worktrees/` directory alongside the repo (e.g. `../.worktrees/odh-dashboard--pr-123-slug`)
2. Offer to copy gitignored files (e.g. `node_modules/`) from the main worktree
3. Detect your editor (VS Code, Cursor) and open a new window
4. Detect the project's dependency manager and show install instructions

Worktrees are created outside the repo directory so they don't need to be gitignored within the project. Add `.worktrees/` to the parent directory's `.gitignore` if it's tracked.

## Cleanup

```bash
# Remove a specific worktree (from the project repo)
git worktree remove ../.worktrees/<name>

# List all worktrees
git worktree list
```
