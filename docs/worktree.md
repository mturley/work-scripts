# worktree

Unified command for creating and managing git worktrees that optionally clone installed dependencies from the main working tree. Accepts a PR number, PR URL, branch name, or worktree path. Provides a REPL with convenient commands for using and cleaning up worktrees.

## Prerequisites

- [GitHub CLI](https://cli.github.com/) (`gh`, must be authenticated)
- Python 3
- For multi-worktree support: [iTerm2](https://iterm2.com/) or [mprocs](https://github.com/pvolok/mprocs) (`brew install mprocs`)
- Optionally, set `WORKTREES_BASE` to control where worktrees are created (default: `~/git/.worktrees`). This should be outside your project git repos.
  ```bash
  export WORKTREES_BASE=$HOME/git/.worktrees
  ```

## Usage

Run `worktree` in multiple terminals to open editors in multiple branches at the same time. This is my preferred way to review multiple PRs in parallel: I use the `/review` skill from my [claude-skills](https://github.com/mturley/claude-skills) repo in each worktree's editor. It is also useful for using agents to work on multiple features/bugs in parallel, especially with the optional depenency linking.

```bash
worktree                             # list existing worktrees and select one
worktree 1234                        # create or reopen a worktree for PR #1234
worktree https://github.com/org/repo/pull/1234
worktree my-feature-branch           # create or reopen a branch worktree
worktree ~/git/.worktrees/repo--name # open an existing worktree by path
worktree 1234 5678 my-branch         # open multiple worktrees in parallel
```

Based on the arguments, the script detects what you're trying to do, finds or creates the relevant worktree, then drops you into an interactive REPL (see below) to manage it.

### Multiple Worktrees

When given multiple arguments, each worktree opens in its own pane:

- **iTerm2** — opens each worktree in a new tab (named "worktree PR #1234", etc.)
- **Fallback** — uses [mprocs](https://github.com/pvolok/mprocs) with a shell pane for running further commands and one pane per worktree. Running `worktree` from the shell pane dynamically adds new panes to the session.

Install mprocs if not using iTerm: `brew install mprocs`

* **No arguments** — if run from within a worktree directory under `$WORKTREES_BASE`, drops directly into the REPL for that worktree. Otherwise, lists all worktrees, detects and marks orphaned ones (`.git` missing but files not fully cleaned up), and lets you select one to manage or clean up. Supports comma-separated selections (e.g. `1,3,5`) or `all` to open multiple worktrees in parallel.

* **PR number or GitHub URL** — fetches the PR and searches for any existing worktrees on related branches (the PR's head ref or a `review/pr-*` branch). If one is found, reuses it with a sync check (offering to back up and reset to the PR's latest commit if behind). If multiple are found, shows a selection with commit info and ahead/behind status. If none are found, creates a new review worktree and sets up branch tracking against the PR author's remote. Automatically locates the matching local repo if run from a different directory.

* **Branch name** — creates a new branch from `upstream/main` (or `origin/main`) in a worktree. If the branch is already checked out elsewhere, offers to reuse or move it. Must be run from within a git repo.

* **Worktree path** — if it matches an existing worktree, drops directly into the REPL for that worktree.

### Cross-Worktree Dependency Cloning

After creating a new worktree, the command prompts you to choose how much to share from the main working tree:

- **`1` — Dotfiles, dependencies and build artifacts** — clones dotfiles plus `node_modules`, `dist/`, `bin/`, etc.
- **`2` — Config only** — clones top-level dotfiles (`.env.local`, `.husky`, etc.). You'll need to install dependencies and build yourself.
- **`3` — Nothing** — skip cloning entirely.

For each category you choose, you can select which specific files to include. Selections are cached separately per repo (in `/tmp`) and offered for reuse next time.

**Copy strategy** — on macOS (APFS), all targets are cloned using `cp -Rc` for copy-on-write clones. These are nearly instant and produce fully independent copies (writes don't affect the original). On other platforms, all targets are copied via `rsync -a` (full independent copies, but slower).

### Opening Editors

It then **detects your editor** (VS Code or Cursor) or uses a cached preference (in `/tmp`), opens an editor window (or focuses an existing one), and drops into the interactive REPL.

### Interactive REPL

Once a worktree is ready, all usage paths above end here. On entry and before each prompt, shows the available commands:

```
worktree> help

  info     (i)  Show PR URL (if applicable), worktree path, tracking status, and git status
  log      (l)  Show git log
  open     (o)  Open worktree in your editor (focuses existing window if already open)
  pr       (p)  Open the pull request page on GitHub (shown when a PR exists for the branch)
  shell    (s)  Start a nested shell in the worktree directory; exit to return to REPL
  cleanup  (c)  Remove the worktree and its branch
  exit     (e)  Exit the REPL
  help     (h)  Show this help

Commands: [i]nfo, [l]og, [o]pen, [p]r, [s]hell, [c]leanup, [e]xit, [h]elp

worktree [my-branch...origin/my-branch]>
```

I leave the REPL open in multiple terminals for quick cleanup of each one, but you can also exit it and run `worktree` again to get back to it. If you want to run a dev environment in the worktree, you can use the `[s]hell` command and run it from within the nested shell.