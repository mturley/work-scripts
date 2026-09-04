# `pull-pr` — Update a PR Review Worktree

Fetches the latest commits on the current worktree's PR and hard-resets the
working tree to them.

Built for review worktrees created by `gh pr checkout`, where the branch's
upstream is a PR head ref (`refs/pull/N/head`) rather than an ordinary branch.
Git accepts that as tracking config but never stores it as a remote-tracking
branch, so the usual shortcuts don't work:

```console
$ git rev-parse --abbrev-ref @{upstream}
fatal: upstream branch 'refs/pull/9565/head' not stored as a remote-tracking branch
$ git pull
# also fails, for the same reason
```

`pull-pr` reads `branch.<name>.remote` and `branch.<name>.merge` from the config
directly, which works whether the upstream is a normal branch or a PR head ref.

## Prerequisites

- `git`
- A worktree whose branch has tracking config pointing at the PR
  (`gh pr checkout` sets this up for you)

## Usage

```bash
pull-pr              # Fetch and reset, pausing before anything destructive
pull-pr --dry-run    # Report what would change, don't reset
pull-pr --force      # Don't pause; proceed even if work would be lost
```

`-y` / `--yes` are accepted as aliases for `--force`.

Run it from inside the worktree you want to update. It takes no PR number —
everything comes from the checked-out branch.

### Example

```console
$ cd ~/.worktrees/odh-dashboard/pr-9565-feat-categorize-pvcs-by-type
$ pull-pr
branch:   review/pr-9565-feat-categorize-pvcs-by-type
upstream: upstream refs/pull/9565/head
current:  c422469f0d7ae9b76430f9738baba78c54c638ff
target:   97d1276ea7cadfbfcbbbfad6f9ab52db33caf74f

Incoming commits:
  97d1276 address review feedback

HEAD is now at 97d1276 address review feedback

Was at c422469f0d7ae9b76430f9738baba78c54c638ff (recover with: git reset --hard c422469…)
```

## Safety

`git reset --hard` is not undoable through normal means, so the script reports
what a reset would destroy and pauses before doing it.

A **clean fast-forward applies immediately, without prompting** — it discards
nothing, so there is nothing to confirm. The script pauses only when the reset
would actually cost you something:

- **Uncommitted changes to tracked files** — the modified paths are listed.
- **A reset that isn't a fast-forward** — meaning the PR author rebased or
  force-pushed, or you have local commits on top. The commits that would be
  lost are listed individually.

Either case prints a `WARNING:` block and then asks:

```console
Reset review/pr-9565-… to 97d1276ea7ca, discarding the above? [y/N]
```

Anything other than `y`/`yes` aborts without touching the worktree. `--force`
skips the prompt for unattended use. **With no TTY** — cron, a pipeline, a
script — there is nothing to prompt on, so it refuses rather than guessing, and
tells you to pass `--force` if you meant it.

The pre-reset SHA is printed on success, so even a confirmed mistake is
recoverable with the `git reset --hard <sha>` line it hands you (or `git reflog`).

**Untracked and ignored files are never touched.** `git reset --hard` only
rewrites tracked files, and this script never runs `git clean` — so `.env.local`,
`node_modules/`, and other gitignored-but-irreplaceable files survive. That's
also why the dirty check uses `git status --untracked-files=no`: untracked files
aren't at risk, so they shouldn't count as a hazard or block an update.

## Implementation notes

- The fetch targets `FETCH_HEAD` rather than a remote-tracking branch, so no `+`
  force prefix is needed. Force-pushed PR branches — the common case — fetch
  cleanly every time.
- **`--dry-run` still fetches.** Fetching only adds objects to the store; it
  moves no branch and touches no file. Having the target commit locally is what
  makes `git merge-base --is-ancestor` possible, and therefore what lets a dry
  run distinguish a fast-forward from a force-push. An `ls-remote`-only dry run
  would be marginally cleaner and would not be able to tell you the one thing
  you most want to know.
- `read` returns non-zero at EOF, which under `set -e` would kill the script
  mid-prompt with no message. The prompt absorbs that and falls through to the
  default (No).
- Notably absent: any GitHub API call. The PR number never appears — the config
  already points at the right ref, so `gh` isn't needed and the script works
  against any remote, including non-GitHub ones.
