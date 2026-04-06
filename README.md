# work-scripts

Personal CLI tools for git, GitHub, and daily workflow automation.

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

## Git Worktree Tools

### [`worktree`](docs/worktree.md)

Create and manage git worktrees for PRs and branches, with optional symlinked dependencies and an interactive REPL.

```bash
worktree                             # list existing worktrees and select one
worktree 1234                        # create or reopen a worktree for PR #1234
worktree https://github.com/org/repo/pull/1234
worktree my-feature-branch           # create or reopen a branch worktree
```

### [`gh-safe`](docs/gh-safe.md)

Safety wrapper for agents using GitHub CLI — read-only operations pass through, write operations require `APPROVE=true`.

```bash
gh-safe pr list                    # passes through (read-only)
gh-safe pr merge 123               # blocked (write operation)
APPROVE=true gh-safe pr merge 123  # allowed
```

## Obsidian Tools

### [`log`](docs/log.md)

Append timestamped, metadata-enriched activity entries to your [Obsidian daily note](https://obsidian.md/help/plugins/daily-notes). Fetches context from GitHub and Jira APIs automatically.

```bash
log                                  # free-form log entry
log pr reviewed org/repo#123         # log a PR review with metadata
log jira seen RHOAIENG-12345         # log viewing a Jira issue
```

Requires the [Obsidian CLI](https://obsidian.md/) and a `.env` file for Jira integration (see [docs](docs/log.md#setup)).
