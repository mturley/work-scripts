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
worktree <pr-number|pr-url|branch-name|worktree-path>
```

**If a worktree already exists** for the given argument, opens an interactive REPL with commands to open the editor, check status, or clean up the worktree.

**If no worktree exists**, detects the argument type and creates one:
- PR number or GitHub PR URL → fetches the PR, creates a review worktree, sets up branch tracking
- Branch name → creates a new branch from `upstream/main` in a worktree

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

When creating a new worktree, the `worktree` command:

1. If run from a workspace containing nested git repos, prompts to select a project repo
2. Creates a worktree in `$WORKTREES_BASE` (default `~/git/.worktrees/`)
3. If the branch is already checked out in another worktree, offers to reuse or move it
4. Offers to copy useful files (node_modules, build outputs, dotfile config) from the main worktree
5. Detects your editor (VS Code, Cursor) or uses your cached preference, and opens a new window
6. Drops into an interactive REPL for managing the worktree

### Cleanup

Use `worktree <arg>` to open the REPL for an existing worktree, then use the `cleanup` command. Or remove directly:

```bash
git worktree remove ~/git/.worktrees/<name>
git worktree list
```
