# worktree

Unified command for creating and managing git worktrees that optionally clone installed dependencies from the main working tree. Accepts a PR number, PR URL, branch name, or worktree path. Provides a REPL with convenient commands for using and cleaning up worktrees.

## Prerequisites

- [GitHub CLI](https://cli.github.com/) (`gh`, must be authenticated)
- Python 3
- [mprocs](https://github.com/pvolok/mprocs) (`brew install mprocs`) for the default multi-pane terminal (shell + worktree panes). Falls back to inline mode if not installed.
- Optionally, [iTerm2](https://iterm2.com/) (with `--iterm`) for multi-worktree split panes/tabs instead of mprocs
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
worktree 1234 5678 my-branch         # open multiple worktrees in mprocs (default)
worktree --iterm 1234 5678           # open multiple worktrees in iTerm split panes
worktree --tabs 1234 5678            # open multiple worktrees in iTerm tabs
worktree --help                      # show usage help
```

Based on the arguments, the script detects what you're trying to do, finds or creates the relevant worktree, then drops you into an interactive REPL (see below) to manage it.

### mprocs Multi-Pane Terminal

By default, every worktree session launches in [mprocs](https://github.com/pvolok/mprocs) with a **shell pane** (for running further commands) and one **worktree pane** per argument. This applies whether you pass one argument or many. Running `worktree` from the shell pane dynamically adds new panes to the session. If mprocs is not installed, falls back to inline mode.

- **iTerm2** — with `--iterm` and multiple arguments, opens each worktree in a vertical split pane (named "worktree PR #1234", etc.). Use `--tabs` to open in separate tabs instead, or `--split` to explicitly request split panes.

* **No arguments** — if run from within any git worktree directory, drops directly into the REPL for that worktree. Otherwise, discovers all worktrees across `$WORKTREE_SEARCH_ROOTS` (including those created by Zed, Claude Code, or any other tool), groups them by repo name, and lets you select one to manage or clean up. Detects and marks orphaned worktrees (`.git` missing) and prunable ones (stale git references). Supports comma-separated selections (e.g. `1,3,5`) or `all` to open multiple worktrees in parallel.

* **PR number or GitHub URL** — fetches the PR metadata (title, author, created/updated dates) and searches for any existing worktrees on related branches (the PR's head ref or a `review/pr-*` branch). Displays the PR title, author, and relative timestamps (e.g. "2 days ago") for when it was created and last updated. If one worktree is found, reuses it with a sync check (offering to back up and reset to the PR's latest commit if behind). If multiple are found, shows a selection with commit info and ahead/behind status. If none are found, creates a new review worktree and sets up branch tracking against the PR author's remote. Automatically locates the matching local repo if run from a different directory.

* **Branch name** — creates a new branch from `upstream/main` (or `origin/main`) in a worktree. If the branch is already checked out elsewhere, offers to reuse or move it. Must be run from within a git repo.

* **Worktree path** — if it matches an existing worktree, drops directly into the REPL for that worktree.

### Opening Editors

After creating a worktree, the script **detects your editor** (VS Code or Cursor) or uses a cached preference (in `/tmp`), and opens an editor window (or focuses an existing one).

### VS Code Auto-REPL

When opening VS Code or Cursor, the script offers to create a `.vscode/tasks.json` in the worktree that auto-starts the REPL in VS Code's integrated terminal when the folder opens. This preference is cached in `/tmp` and can be reset via `--cleanup`.

The `.vscode/` directory is added to the repo's `.git/info/exclude` (with a marker comment) so it doesn't pollute `git status`. When the last worktree for a repo is removed, the exclude entry is automatically cleaned up.

If auto-REPL is enabled, the terminal session that launched the editor exits (with a hint to close the mprocs pane if applicable) since the REPL will run inside VS Code instead.

### Cross-Worktree Dependency Cloning

The `[c]lone files` REPL command lets you share files from the main working tree with a worktree:

- **`1` — Dotfiles, dependencies and build artifacts** — clones dotfiles plus `node_modules`, `dist/`, `bin/`, etc.
- **`2` — Config only** — clones top-level dotfiles (`.env.local`, `.husky`, etc.). You'll need to install dependencies and build yourself.
- **`3` — Nothing** — skip cloning entirely.

For each category you choose, you can select which specific files to include. Selections are cached separately per repo (in `/tmp`) and offered for reuse next time.

**Copy strategy** — on macOS (APFS), all targets are cloned using `cp -Rc` for copy-on-write clones (writes don't affect the original). On other platforms, all targets are copied via `rsync -a`.

### Interactive REPL

Once a worktree is ready, all usage paths above end here (unless VS Code auto-REPL is enabled, in which case the REPL starts in VS Code's terminal instead). On entry, a tip is shown reminding you to use `[c]lone files` to reuse installed dependencies from the main repo. Before each prompt, the available commands are shown:

```
worktree> help

  info     (i)  Show PR info with author and dates (if applicable), worktree path, tracking status, and git status
  log      (l)  Show git log
  open     (o)  Open worktree in your editor (focuses existing window if already open)
  pr       (p)  Open the pull request page on GitHub (if applicable)
  clone    (c)  Clone gitignored files (dotfiles, dependencies) from the main repo
  shell    (s)  Start a nested shell in the worktree directory; exit to return to REPL
  remove   (r)  Remove the worktree and its branch
  exit     (e)  Exit the REPL
  help     (h)  Show this help

Commands: [i]nfo, [l]og, [o]pen, [p]r, [c]lone files, [s]hell, [r]emove, [e]xit, [h]elp

worktree [my-branch...origin/my-branch]>
```

I leave the REPL open in multiple terminals for quick cleanup of each one, but you can also exit it and run `worktree` again to get back to it. If you want to run a dev environment in the worktree, you can use the `[s]hell` command and run it from within the nested shell.

### Persistent Sessions

By default, mprocs sessions are ephemeral — closing the terminal kills the session and all its processes. With the `--persistent` (or `-P`) flag, mprocs runs inside a tmux session that survives terminal disconnects and can be reattached later.

```bash
worktree -P 1234                   # create a persistent session
worktree -P 1234 5678              # persistent multi-worktree session
worktree --sessions                # list active persistent sessions
worktree --kill-session wt-PR-1234 # kill a persistent session
```

To make persistence the default, set the environment variable:
```bash
export WORKTREE_PERSISTENT=true
```

**How it works:**
- A tmux session is created with a name derived from the arguments (e.g. `wt-PR-1234`)
- mprocs runs inside tmux, which provides detach/reattach capability
- Detach with `Ctrl+b d` — the session keeps running in the background
- Reattach by running `worktree -P` with the same arguments, or `tmux attach -t <session-name>`
- If you reattach with additional arguments, new panes are added to the existing session

**Mobile-friendly configuration:**
When using persistent sessions (especially over SSH from a phone):
- `WORKTREE_HIDE_KEYMAP` — hide the keybinding help bar to save vertical space (default: `true` in persistent mode)

Use the mprocs **zoom** command (`z` key) to expand the terminal pane to full screen, hiding the sidebar entirely. Press `z` again to unzoom. Use `Ctrl+a` to switch between processes while zoomed.

See [remote-access.md](remote-access.md) for a guide on setting up SSH access from a phone.