# work-scripts

Personal CLI tools for git, GitHub, and daily workflow automation.

**Commands for Git and GitHub**
- [`worktree`](src/worktree/) — Create and manage git worktrees for PRs and branches
- [`pr-ci`](src/pr-ci/) — Check or watch CI status for a GitHub PR
- [`gh-safe`](src/gh-safe/) — AI agent guardrail for the GitHub CLI
- [`dev-ports`](src/dev-ports/) — Find dev servers running in git repos, grouped by repo and branch

**Commands for Obsidian Notes**
- [`worklog`](src/worklog/) — Append timestamped activity entries to your Obsidian daily note
- [`prep`](src/prep/) — Copy focus and deferred items from the previous daily note to today's
- [`eod`](src/eod/) — Set up tomorrow's focus by carrying over unchecked items
- [`enrich-daily-links`](src/enrich-daily-links/) — Enrich GitHub/Jira/Slack URLs in today's daily note with descriptive markdown links

**Commands for Claude Code**
- [`milestones`](src/milestones/) — Show upcoming RHOAI release milestones via Claude Code
- [`claude-sessions`](src/claude-sessions/) — List all Claude Code sessions across projects
- [`claude-resume`](src/claude-resume/) — Resume a Claude Code session from any directory

**Commands for iTerm2**
- [`iterm-new`](src/iterm-new/) — Open a new iTerm2 tab or split pane and run a command

## Setup

Clone the repo and add its `bin` subdirectory to your PATH:

```bash
git clone git@github.com:mturley/work-scripts.git ~/git/work-scripts
export PATH=$HOME/git/work-scripts/bin:$PATH  # add to ~/.zshrc or ~/.bashrc
```

Further prerequisites and setup for each command are documented in its README in the `src/` directory.

## Commands for Git and GitHub

### [`dev-ports`](src/dev-ports/) — Dev Server Port Finder

Find listening TCP ports whose process is running in a git repo, grouped by repo and branch/worktree. Useful for tracking down which terminals have dev servers running and on what branches.

```bash
dev-ports    # list all dev servers grouped by repo and branch
```

### [`worktree`](src/worktree/) — Git Worktree Manager

Create and manage git worktrees for PRs and branches, with optional cloned dependencies, VS Code auto-REPL integration, and an interactive REPL. Discovers worktrees created by any tool (Zed, Claude Code, etc.) across configurable search roots. Displays PR metadata (title, author, created/updated timestamps) when working with PRs.

```bash
worktree                             # list worktrees; select one, many (1,3,5), or all
worktree 1234                        # create or reopen a worktree for PR #1234
worktree https://github.com/org/repo/pull/1234
worktree my-feature-branch           # create or reopen a branch worktree
worktree 1234 5678 my-branch         # open multiple worktrees in mprocs
worktree --standalone my-branch      # shell in worktree, no mprocs
worktree --no-persist 1234           # skip screen, mprocs only
worktree --sessions                  # list active persistent sessions
worktree --help                      # show usage help
```

Sessions are persistent by default (mprocs runs inside GNU Screen 5.0+ for detach/reattach). Use `--no-persist` to skip screen. When running inside [cmux](https://cmux.com/), workspaces and splits are used instead of mprocs/screen.

```
[h]elp     [i]nfo     [n]ame     [q]uit
[l]og      [f]iles    [d]elete
[e]ditor   [p]r       [s]hell    [c]laude

worktree [my-branch...origin/my-branch]>
```

### [`pr-ci`](src/pr-ci/) — PR CI Status Checker

Check or watch CI status for a GitHub PR. Shows a summary of passed/failed/pending checks; watch mode polls and sends a macOS alert when done.

```bash
pr-ci 6999                 # watch CI, poll every 2 minutes, alert when done
pr-ci 6999 60              # watch CI, poll every 60 seconds
pr-ci 6999 --once          # one-shot status summary
```

### [`gh-safe`](src/gh-safe/) — AI Agent Guardrail for GitHub CLI

Safety wrapper for the GitHub CLI for use with AI agents — read-only operations pass through, write operations require explicit `APPROVE=true`.

```bash
gh-safe pr list                    # passes through (read-only)
gh-safe pr merge 123               # blocked (write operation)
APPROVE=true gh-safe pr merge 123  # allowed
```

## Commands for Obsidian Notes

### [`worklog`](src/worklog/) — Activity Logger

Append timestamped, metadata-enriched activity entries to your [Obsidian daily note](https://obsidian.md/help/plugins/daily-notes). Fetches context from GitHub and Jira APIs automatically. Also available as `wlog`.

```bash
worklog                                  # free-form log entry
worklog pr reviewed org/repo#123         # log a PR review with metadata
worklog jira seen RHOAIENG-12345         # log viewing a Jira issue
worklog combine                          # consolidate duplicate entries
worklog undo                             # remove the last activity log entry
```

Requires the [Obsidian CLI](https://obsidian.md/) and a `.env` file. Jira integration requires an external secrets file (see [setup](src/worklog/#setup)).

### [`prep`](src/prep/) — Morning Prep

Copy focus and deferred items from the most recent previous daily note to today's note. Handles gaps and weekends automatically.

```bash
prep         # copy items from the previous note to today
```

### [`eod`](src/eod/) — End of Day

Set up tomorrow's focus by carrying over unchecked items from today's focus section.

```bash
eod                # process today's note
eod yesterday      # process the most recent previous note
eod friday         # process the most recent Friday note (handy on Monday)
eod "Apr 3"        # process a specific date
```

### [`enrich-daily-links`](src/enrich-daily-links/) — Daily Note Link Enricher

Enrich GitHub PR, Jira, and Slack URLs in today's daily note with descriptive markdown links. GitHub PR links include the PR title fetched via the `gh` CLI. Jira links include the issue type and title fetched from the Jira API. Slack links are labeled "Slack thread". Handles bare URLs, markdown links with URL as text, HTML links, and existing links with just `repo#number` or a Jira key as text.

```bash
enrich-daily-links            # enrich links in today's note
enrich-daily-links --dry-run  # preview changes without modifying
```

## Commands for Claude Code

### [`milestones`](src/milestones/) — RHOAI Release Milestones

Show upcoming RHOAI release milestones from Product Pages. Runs the `/milestones` Claude Code skill with the default model.

```bash
milestones                     # major releases, next 3 months
milestones 6 months            # major releases, next 6 months
milestones 3.5                 # all 3.5 milestones (EA1, EA2, GA)
milestones through 3.6         # major milestones through 3.6 GA
milestones all                 # all releases including patches, next 3 months
```

### [`claude-sessions`](src/claude-sessions/) — Session Browser

List all Claude Code sessions across all projects, most recent first. Shows session ID, working directory, first user message ("name"), and last user message. Pages 5 at a time.

```bash
claude-sessions        # list sessions, 5 at a time
```

### [`claude-resume`](src/claude-resume/) — Resume From Anywhere

Resume a Claude Code session from any directory. Looks up the session's working directory automatically.

```bash
claude-resume f5e4d769-7848-4b7b-9e3f-443689550bf3
```

## Commands for iTerm2

### [`iterm-new`](src/iterm-new/) — New Tab or Split Pane

Open a new [iTerm2](https://iterm2.com/) tab or split pane and run a command. The tab/pane is named after the command or a custom name.

```bash
iterm-new tab npm run dev            # new tab
iterm-new split-v npm run dev        # vertical split
iterm-new split-h npm run dev        # horizontal split
iterm-new tab -n "my app" npm start  # new tab with custom name
```

