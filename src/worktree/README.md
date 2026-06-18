# worktree

Unified command for creating and managing git worktrees that optionally clone installed dependencies from the main working tree. Accepts a PR number, PR URL, branch name, or worktree path. Provides a REPL with convenient commands for using and cleaning up worktrees.

## Prerequisites

- [GitHub CLI](https://cli.github.com/) (`gh`, must be authenticated)
- Python 3
- [mprocs](https://github.com/pvolok/mprocs) (`brew install mprocs`) for the multi-pane terminal (shell + worktree panes). Falls back to inline mode if not installed.
- Optionally, set `WORKTREES_BASE` to control where worktrees are created (default: `~/git/.worktrees`). This should be outside your project git repos.
  ```bash
  export WORKTREES_BASE=$HOME/git/.worktrees
  ```
- Optionally, configure worktree discovery to find worktrees created by other tools (Zed, Claude Code, etc.):
  ```bash
  export WORKTREE_SEARCH_ROOTS=$HOME/git        # colon-separated search roots (default: ~/git)
  export WORKTREE_SEARCH_DEPTH=5                 # max find depth (default: 5)
  export WORKTREE_SEARCH_PRUNE=node_modules:.Trash:.cache:.venv:venv  # dirs to skip (default)
  ```

## Usage

Run `worktree` in multiple shells (or run it once with multiple arguments to spawn it in multiple shells) to set up worktrees and open editors in multiple branches at the same time. This is my preferred way to review multiple PRs in parallel: I use the `/review` skill from my [claude-skills](https://github.com/mturley/claude-skills) repo in each worktree's editor. It is also useful for using agents to work on multiple features/bugs in parallel, especially with the optional depenency linking.

```bash
worktree                             # list existing worktrees and select one
worktree 1234                        # create or reopen a worktree for PR #1234
worktree https://github.com/org/repo/pull/1234
worktree my-feature-branch           # create or reopen a branch worktree
worktree ~/git/.worktrees/repo/name  # open an existing worktree by path
worktree 1234 5678 my-branch         # open multiple worktrees in mprocs
worktree --standalone my-branch      # shell in worktree, no mprocs
worktree --help                      # show usage help
```

Based on the arguments, the script detects what you're trying to do, finds or creates the relevant worktree, then drops you into an interactive REPL (see below) to manage it.

### mprocs Multi-Pane Terminal

By default, every worktree session launches in [mprocs](https://github.com/pvolok/mprocs) with a **shell pane** (for running further commands) and one **worktree pane** per argument. This applies whether you pass one argument or many. Running `worktree` from the shell pane dynamically adds new panes to the session. If mprocs is not installed, falls back to inline mode.

* **No arguments** — if run from within any git worktree directory, drops directly into the REPL for that worktree. Otherwise, discovers all worktrees across `$WORKTREE_SEARCH_ROOTS` (including those created by Zed, Claude Code, or any other tool), groups them by repo name, and lets you select one to manage or clean up. Detects and marks orphaned worktrees (`.git` missing) and prunable ones (stale git references). Supports comma-separated selections (e.g. `1,3,5`) or `all` to open multiple worktrees in parallel.

* **PR number or GitHub URL** — fetches the PR metadata (title, author, created/updated dates) and searches for any existing worktrees on related branches (the PR's head ref or a `review/pr-*` branch). Displays the PR title, author, and relative timestamps (e.g. "2 days ago") for when it was created and last updated. If one worktree is found, reuses it with a sync check (offering to back up and reset to the PR's latest commit if behind). If multiple are found, shows a selection with commit info and ahead/behind status. If none are found, creates a new review worktree and sets up branch tracking against the PR author's remote. Automatically locates the matching local repo if run from a different directory.

* **Branch name** — creates a new branch from `upstream/main` (or `origin/main`) in a worktree. If the branch is already checked out elsewhere, offers to reuse or move it. Must be run from within a git repo.

* **Worktree path** — if it matches an existing worktree, drops directly into the REPL for that worktree.

### Opening Editors

By default, the REPL does not automatically open an editor. Use the `--open` flag to detect your editor (VS Code or Cursor) or use a cached preference (in `/tmp`) and open a window (or focus an existing one). The REPL's `[e]ditor` command is always available to open an editor on demand.

### Cross-Worktree Dependency Cloning

The `[f]iles` REPL command lets you clone files from the main working tree into a worktree:

- **`1` — Dotfiles, dependencies and build artifacts** — clones dotfiles plus `node_modules`, `dist/`, `bin/`, etc.
- **`2` — Config only** — clones top-level dotfiles (`.env.local`, `.husky`, etc.). You'll need to install dependencies and build yourself.
- **`3` — Nothing** — skip cloning entirely.

For each category you choose, you can select which specific files to include. Selections are cached separately per repo (in `/tmp`) and offered for reuse next time.

**Copy strategy** — on macOS (APFS), all targets are cloned using `cp -Rc` for copy-on-write clones (writes don't affect the original). On other platforms, all targets are copied via `rsync -a`.

### Interactive REPL

Once a worktree is ready, all usage paths above end here. On entry, a tip is shown reminding you to type `files` to clone installed dependencies from the main repo. Type a command and press Enter (both single-letter shortcuts and full words work):

```
worktree> help

  Navigation
    h  help      Show this help
    i  info      Show worktree path, git status, PR info, and Jira details
    l  log       Show git log
    q  quit      Exit the REPL

  Manage
    f  files     Clone gitignored files (dotfiles, dependencies) from the main worktree
    p  prefs     Show saved preferences and optionally clean them up
    n  name      Rename this mprocs pane or cmux workspace
    d  delete    Remove the worktree and its branch

  Open
    e  editor    Open worktree in your editor (focuses existing window if already open)
    s  shell     Start a shell in the worktree
    c  claude    Start Claude Code in the worktree
    g  github    Open the pull request page on GitHub (if applicable)
    j  jira      Open/add associated Jira issues (primary or related)

help       info       log        quit
files      prefs      name       delete
editor     shell      claude     github     jira

worktree [my-branch...origin/my-branch]>
```

I leave the REPL open in multiple terminals for quick cleanup of each one, but you can also exit it and run `worktree` again to get back to it. If you want to run a dev environment in the worktree, you can use `shell` — in mprocs it starts a nested session with a `[worktree]` pane (running the REPL) and a shell pane; in cmux or standalone mode it opens an inline subshell.

### Persistent Sessions

By default, mprocs sessions run inside a GNU Screen session that survives terminal disconnects and can be reattached later. Use `--no-persist` to skip screen wrapping.

**Requires GNU Screen >= 5.0** (macOS ships 4.0 which lacks mouse support). Install with `brew install screen` and ensure Homebrew's screen is on PATH before `/usr/bin/screen`.

```bash
worktree 1234                      # persistent session (default)
worktree 1234 5678                 # persistent multi-worktree session
worktree --open 1234               # auto-open editor on REPL entry
worktree --no-persist 1234         # skip screen, mprocs only
worktree --ports                   # show allocated port ranges
worktree --sessions                # list active persistent sessions
worktree --kill-session wt-all     # kill the persistent session
```

To disable persistence by default, set the environment variable:
```bash
export WORKTREE_PERSISTENT=false
```

**How it works:**
- All persistent sessions use a single canonical screen session named `wt-all`
- mprocs runs inside screen, which provides detach/reattach capability
- Detach with `Ctrl+a d` — the session keeps running in the background
- Quitting mprocs (`q` or `Q`) automatically exits the screen session
- When creating a new session, all existing worktrees are automatically included alongside the requested ones
- When adding to an existing session, new worktrees are added as panes (duplicates are skipped)
- Reattach by running `worktree` with any arguments, or `screen -r wt-all`
- Running `worktree` with no arguments in persistent mode auto-selects all discovered worktrees

### Standalone Mode

Use `--standalone` to skip mprocs and screen entirely. The script resolves or creates the worktree, then opens a new shell in its directory. Exit the shell to return to where you started.

```bash
worktree --standalone my-branch        # shell in worktree, no mprocs
worktree my-branch --standalone        # flags work in any position
```

Only works with a single worktree argument. Useful when you just want to `cd` into a worktree without the full mprocs/REPL experience.

### Port Ranges

Each worktree is automatically assigned a unique port range (starting at 4020, 10 ports per worktree) so dev servers in different worktrees don't collide. The `WORKTREE_PORTS` environment variable is set in the worktree's shell with the assigned range. Use `worktree --ports` to view allocated ranges and free stale entries for removed worktrees.

### Renaming

Inside a worktree REPL, use the `name` command to rename the mprocs pane or cmux workspace:

```
worktree [my-branch]> name my-custom-name    # rename the pane/workspace
worktree [my-branch]> name                   # reset to default name
```

**Mobile-friendly configuration:**
When using persistent sessions (especially over SSH from a phone):
- `WORKTREE_HIDE_KEYMAP` — hide the keybinding help bar to save vertical space (default: `true` in persistent mode)

Use the mprocs **zoom** command (`z` key) to expand the terminal pane to full screen, hiding the sidebar entirely. Press `z` again to unzoom. Use `Ctrl+a` to switch between processes while zoomed.

See [remote-access.md](remote-access.md) for a guide on setting up SSH access from a phone.

## cmux Integration

When running inside [cmux](https://cmux.com/), the worktree script automatically detects the environment via the `CMUX_SOCKET_PATH` variable and uses cmux workspaces instead of mprocs/screen:

- **Workspace layout** → each worktree gets a cmux workspace with a split layout:
  - **Top-left (1/3 height):** two terminal tabs — a generic shell and the worktree REPL
  - **Bottom-left (2/3 height):** `cmux claude-teams` for AI-assisted development
  - **Right (50% width, optional):** browser tabs for the associated PR and/or Jira issue, shown when URLs are detected
- **Persistence** → handled natively by cmux (screen is skipped entirely)
- **Shell/Claude commands** → run inline in the current terminal (exit to return to REPL)
- **Rename** → renames the cmux workspace instead of an mprocs pane
- **Deduplication** → before creating a workspace, checks existing workspaces by working directory and switches to a match instead of creating a duplicate
- **No-args discovery** → shows which worktrees already have cmux workspaces open (marked `[open]`); single selection switches to or creates a workspace, multiple selection opens only missing ones

The `--no-persist` and `--standalone` flags are effectively no-ops when running in cmux.

## Jira Integration

The worktree script can detect Jira issue keys associated with a worktree and offer a `[j]ira` command to open them in your browser. Detected issues also appear in the `--info` output.

### Configuration

Add `JIRA_PROJECTS` to your Jira secrets env file (the file pointed to by `JIRA_SECRETS_ENV` in `.env`):

```bash
export JIRA_PROJECTS=RHOAIENG,RHOAI,ODH
```

This is a comma-separated list of Jira project prefixes to scan for in branch names and PR descriptions.

### Detection

Jira issue keys are detected from three sources (in order):
1. **Cached associations** — previously associated issues stored in `.worktree-resources`
2. **Branch name** — e.g. branch `RHOAIENG-12345-fix-pagination` detects `RHOAIENG-12345`
3. **PR title and body** — if a PR is detected, its title and description are scanned for issue keys

### API Enrichment

When `JIRA_HOST`, `JIRA_EMAIL`, and `JIRA_TOKEN` are all configured, the script fetches metadata (title, type, priority, status, assignee) from the Jira REST API and displays it with emoji indicators:
- Issue types: 🐛 Bug, 📖 Story, ✅ Task, ⚡ Epic
- Priorities: 🔴 Blocker, 🟠 Critical, 🟡 Major, 🔵 Normal, 🟢 Minor

If credentials are not configured or the API call fails (expired token, network error), the script silently falls back to showing just the issue key and URL.

### Manual Association

Pressing `[j]ira` in the REPL opens the associated issue (or shows a picker if multiple exist). If no issue is detected, it prompts you to paste a Jira issue key or URL. When adding an issue, you choose whether it's **primary** (the issue this worktree is working on — replaces any existing primary) or **related** (watching for context — appended). Associations are saved in `.worktree-resources` and persist across REPL sessions.

### Worktree Environment File

A `.worktree-env` file is automatically generated in each worktree directory, exporting `WORKTREE_PORTS`, `WORKTREE_TITLE`, `WORKTREE_PATH`, and `KUBECONFIG`. On first use, the script offers to add an auto-source snippet to your shell RC file (`.zshrc`, `.bashrc`, or `config.fish`) so these variables are available in any terminal opened in the worktree directory. The file displays a lightweight summary once per shell session via `worktree --info-simple` (path, branch, environment, current oc context — no API calls). Run `worktree --info` for full PR and Jira status.

### External Resources File

A `.worktree-resources` file tracks PRs and Jira issues associated with the worktree. Each line is `<type>:<id> <url>`, with an optional `~ ` prefix for related (context-watching) resources:

```
pr:owner/repo#123 https://github.com/owner/repo/pull/123
jira:RHOAIENG-456 https://redhat.atlassian.net/browse/RHOAIENG-456
~ jira:RHOAIENG-400 https://redhat.atlassian.net/browse/RHOAIENG-400
```

Unmarked lines are **primary** (the reason this worktree exists). Lines prefixed with `~ ` are **related** (watching for context). Primary resources get full detail in `worktree --info`; related resources are shown as compact one-liners. This file is tool-agnostic — other worktree-aware tools can read or write it.

The `KUBECONFIG` is set to `~/.kube/config-<worktree-name>`, giving each worktree an isolated kubeconfig. On first setup, the file is seeded from your current kubeconfig (from `$KUBECONFIG` or `~/.kube/config`) so the worktree inherits your active cluster context. The kubeconfig file is cleaned up when the worktree is removed via `worktree --cleanup`.

If you use Powerlevel10k with instant prompt, the setup will change `POWERLEVEL9K_INSTANT_PROMPT` to `quiet` in `~/.p10k.zsh` to allow the info output without warnings.