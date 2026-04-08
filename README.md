# work-scripts

Personal CLI tools for git, GitHub, and daily workflow automation.

**Commands for Git and GitHub**
- [`worktree`](docs/worktree.md) — Create and manage git worktrees for PRs and branches
- [`pr-ci`](docs/pr-ci.md) — Check or watch CI status for a GitHub PR
- [`gh-safe`](docs/gh-safe.md) — AI agent guardrail for the GitHub CLI

**Commands for Obsidian Notes**
- [`worklog`](docs/worklog.md) — Append timestamped activity entries to your Obsidian daily note
- [`prep`](docs/prep.md) — Copy focus and deferred items from the previous daily note to today's
- [`eod`](docs/eod.md) — Set up tomorrow's focus by carrying over unchecked items
- [`enrich-daily-links`](docs/enrich-daily-links.md) — Enrich GitHub/Jira URLs in today's daily note with descriptive markdown links

**Commands for iTerm2**
- [`iterm-new`](docs/iterm-new.md) — Open a new iTerm2 tab or split pane and run a command

## Setup

Clone the repo and add its `bin` subdirectory to your PATH:

```bash
git clone git@github.com:mturley/work-scripts.git ~/git/work-scripts
export PATH=$HOME/git/work-scripts/bin:$PATH  # add to ~/.zshrc or ~/.bashrc
```

Further prerequisites and setup for each command are documented in its [docs file](docs/).

## Commands for Git and GitHub

### [`worktree`](docs/worktree.md) — Git Worktree Manager

Create and manage git worktrees for PRs and branches, with optional cloned dependencies and an interactive REPL.

```bash
worktree                             # list worktrees; select one, many (1,3,5), or all
worktree 1234                        # create or reopen a worktree for PR #1234
worktree https://github.com/org/repo/pull/1234
worktree my-feature-branch           # create or reopen a branch worktree
worktree 1234 5678 my-branch         # open multiple worktrees in split panes
worktree --tabs 1234 5678            # open multiple worktrees in separate tabs
worktree --help                      # show usage help
```

```
Commands: [i]nfo, [l]og, [o]pen, [p]r, [s]hell, [c]leanup, [e]xit, [h]elp

worktree [my-branch...origin/my-branch]>
```

### [`pr-ci`](docs/pr-ci.md) — PR CI Status Checker

Check or watch CI status for a GitHub PR. Shows a summary of passed/failed/pending checks; watch mode polls and sends a macOS alert when done.

```bash
pr-ci 6999                 # watch CI, poll every 2 minutes, alert when done
pr-ci 6999 60              # watch CI, poll every 60 seconds
pr-ci 6999 --once          # one-shot status summary
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
worklog undo                             # remove the last activity table row
```

Requires the [Obsidian CLI](https://obsidian.md/) and a `.env` file for Jira integration (see [docs](docs/worklog.md#setup)).

### [`prep`](docs/prep.md) — Morning Prep

Copy focus and deferred items from the most recent previous daily note to today's note. Handles gaps and weekends automatically.

```bash
prep         # copy items from the previous note to today
```

### [`eod`](docs/eod.md) — End of Day

Set up tomorrow's focus by carrying over unchecked items from today's focus section.

```bash
eod                # process today's note
eod yesterday      # process the most recent previous note
eod friday         # process the most recent Friday note (handy on Monday)
eod "Apr 3"        # process a specific date
```

### [`enrich-daily-links`](docs/enrich-daily-links.md) — Daily Note Link Enricher

Enrich GitHub PR and Jira URLs in today's daily note with descriptive markdown links. Jira links include the issue type and title fetched from the Jira API. Handles bare URLs, markdown links with URL as text, HTML links, and existing Jira links with just the key as text.

```bash
enrich-daily-links            # enrich links in today's note
enrich-daily-links --dry-run  # preview changes without modifying
```

## Commands for iTerm2

### [`iterm-new`](docs/iterm-new.md) — New Tab or Split Pane

Open a new [iTerm2](https://iterm2.com/) tab or split pane and run a command. The tab/pane is named after the command or a custom name.

```bash
iterm-new tab npm run dev            # new tab
iterm-new split-v npm run dev        # vertical split
iterm-new split-h npm run dev        # horizontal split
iterm-new tab -n "my app" npm start  # new tab with custom name
```
