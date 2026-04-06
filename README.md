# work-scripts

Personal CLI tools for git, GitHub, and daily workflow automation.

- [`worktree`](docs/worktree.md) — Create and manage git worktrees for PRs and branches
- [`gh-safe`](docs/gh-safe.md) — AI agent guardrail for the GitHub CLI
- [`worklog`](docs/worklog.md) (or `wlog`) — Append timestamped activity entries to your [Obsidian daily note](https://obsidian.md/help/plugins/daily-notes)
- [`iterm-split`](docs/iterm-split.md) — Split iTerm2 and run a command in the new pane

## Setup

Clone the repo and add its `bin` subdirectory to your PATH:

```bash
git clone git@github.com:mturley/work-scripts.git ~/git/work-scripts
export PATH=$HOME/git/work-scripts/bin:$PATH  # add to ~/.zshrc or ~/.bashrc
```

Further prerequisites and setup for each command are documented in its [docs file](docs/).

## Commands for Git and GitHub

### [`worktree`](docs/worktree.md) — Git Worktree Manager

Create and manage git worktrees for PRs and branches, with optional symlinked dependencies and an interactive REPL.

```bash
worktree                             # list existing worktrees and select one
worktree 1234                        # create or reopen a worktree for PR #1234
worktree https://github.com/org/repo/pull/1234
worktree my-feature-branch           # create or reopen a branch worktree
```

```
Commands: [i]nfo, [l]og, [o]pen, [p]r, [s]hell, [c]leanup, [e]xit, [h]elp

worktree [my-branch...origin/my-branch]>
```

### [`gh-safe`](docs/gh-safe.md) — AI Agent Guardrail for GitHub CLI

Safety wrapper for the GitHub CLI for use with AI agents — read-only operations pass through, write operations require explicit `APPROVE=true`.

```bash
gh-safe pr list                    # passes through (read-only)
gh-safe pr merge 123               # blocked (write operation)
APPROVE=true gh-safe pr merge 123  # allowed
```

## Commands for Obsidian Notes

### [`worklog`](docs/worklog.md) — Activity Logger

Append timestamped, metadata-enriched activity entries to your [Obsidian daily note](https://obsidian.md/help/plugins/daily-notes). Fetches context from GitHub and Jira APIs automatically. Also available as `wlog`.

```bash
worklog                                  # free-form log entry
worklog pr reviewed org/repo#123         # log a PR review with metadata
worklog jira seen RHOAIENG-12345         # log viewing a Jira issue
```

Requires the [Obsidian CLI](https://obsidian.md/) and a `.env` file for Jira integration (see [docs](docs/worklog.md#setup)).

## Commands for iTerm2

### [`iterm-split`](docs/iterm-split.md) — Split and Run

Split the current [iTerm2](https://iterm2.com/) window and run a command in the new pane. The pane is named after the command for easy identification.

```bash
iterm-split npm run dev              # vertical split (default)
iterm-split -v npm run dev           # vertical split (explicit)
iterm-split -h npm run dev           # horizontal split
```
