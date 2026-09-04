#!/usr/bin/env bash
#
# pull-pr — fetch the latest commits on the current worktree's PR and hard-reset
# to them.
#
# Operates on the current worktree only, deriving everything from the checked-out
# branch's tracking config. Intended for review worktrees created by
# `gh pr checkout`, where the upstream is a PR head ref (refs/pull/N/head) that
# is never stored as a remote-tracking branch.
#
# Usage:
#   pull-pr            Fetch and reset, pausing before anything destructive
#   pull-pr --force    Don't pause; proceed even if work would be lost
#   pull-pr --dry-run  Show what would happen, change nothing
#

set -euo pipefail

# ── Usage ───────────────────────────────────────────────────────────────

usage() {
  cat <<'EOF'
Usage: pull-pr [--force] [--dry-run]

  Fetches the current branch's configured upstream ref and hard-resets the
  working tree to it. Run from inside the worktree you want to update.

  -f, --force     Don't pause for confirmation, even when the reset would
                  discard uncommitted changes or local commits
                  (-y / --yes are accepted as aliases)
  -n, --dry-run   Report what would change, but don't reset
  -h, --help      Show this help

Examples:
  pull-pr                  Update this worktree to the tip of its PR
  pull-pr --dry-run        Check whether the PR has moved, and how
  pull-pr --force          Update unattended, throwing away local work

A clean fast-forward applies without prompting, since it discards nothing.
Anything destructive prompts first, showing exactly what would be lost. With
no TTY (cron, scripts) there is nothing to prompt, so it refuses unless --force.

Untracked and ignored files (.env.local, build output, etc.) are never touched
— `git reset --hard` leaves them alone, and this script never runs `git clean`.
EOF
  exit 1
}

FORCE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)          usage ;;
    -f|--force|-y|--yes) FORCE=true; shift ;;
    -n|--dry-run)       DRY_RUN=true; shift ;;
    *)
      echo "pull-pr: unknown argument: $1" >&2
      echo >&2
      usage
      ;;
  esac
done

die() {
  echo "pull-pr: $*" >&2
  exit 1
}

# ── Locate the branch and its upstream ──────────────────────────────────

git rev-parse --git-dir >/dev/null 2>&1 || die "not inside a git repository"

BRANCH=$(git rev-parse --abbrev-ref HEAD)
[[ "$BRANCH" == "HEAD" ]] && die "HEAD is detached; check out the PR branch first"

# Read the tracking config directly rather than using @{upstream}. A PR head ref
# (refs/pull/N/head) is a valid upstream but has no remote-tracking branch, so
# `git rev-parse @{upstream}` fails on exactly the branches this script targets.
REMOTE=$(git config --get "branch.$BRANCH.remote") \
  || die "branch '$BRANCH' has no upstream remote configured"
MERGE=$(git config --get "branch.$BRANCH.merge") \
  || die "branch '$BRANCH' has no upstream ref configured"

echo "branch:   $BRANCH"
echo "upstream: $REMOTE $MERGE"

# --untracked-files=no is deliberate: reset --hard only rewrites tracked files,
# so untracked ones are not at risk and shouldn't count as a hazard.
DIRTY=$(git status --porcelain --untracked-files=no)

# ── Fetch ───────────────────────────────────────────────────────────────

BEFORE=$(git rev-parse HEAD)

# Fetch even on a dry run. It only adds objects — no branch moves, no working
# tree changes — and having the target locally is what makes the ancestry check
# below possible. Without it a dry run couldn't tell a fast-forward from a
# force-push, which is the single most important thing to report.
#
# No '+' prefix needed: fetching into FETCH_HEAD rather than a tracking ref
# accepts force-pushed PR branches without complaint.
git fetch "$REMOTE" "$MERGE"
TARGET=$(git rev-parse FETCH_HEAD)

echo "current:  $BEFORE"
echo "target:   $TARGET"

if [[ "$TARGET" == "$BEFORE" ]]; then
  echo "Already up to date."
  [[ -n "$DIRTY" ]] && echo "(Local modifications left untouched.)"
  exit 0
fi

# ── Work out what, if anything, the reset would destroy ─────────────────

FAST_FORWARD=true
git merge-base --is-ancestor "$BEFORE" "$TARGET" || FAST_FORWARD=false

# Empty when the target is behind or diverged, so only print the header if
# there is actually something to list.
INCOMING=$(git log --oneline --no-decorate "$BEFORE".."$TARGET")
if [[ -n "$INCOMING" ]]; then
  echo
  echo "Incoming commits:"
  echo "$INCOMING" | sed 's/^/  /'
fi

HAZARD=false

if ! $FAST_FORWARD; then
  HAZARD=true
  echo
  echo "WARNING: not a fast-forward — the PR was rebased or force-pushed, or"
  echo "this worktree has local commits. Resetting DISCARDS these commits:"
  echo
  git log --oneline --no-decorate "$TARGET".."$BEFORE" | sed 's/^/  /'
fi

if [[ -n "$DIRTY" ]]; then
  HAZARD=true
  echo
  echo "WARNING: uncommitted changes to tracked files. Resetting DISCARDS them:"
  echo
  echo "$DIRTY" | sed 's/^/  /'
fi

# ── Confirm ─────────────────────────────────────────────────────────────

if $DRY_RUN; then
  echo
  if $HAZARD; then
    echo "Dry run: would reset $BRANCH to $TARGET, destroying the above."
  else
    echo "Dry run: would fast-forward $BRANCH to $TARGET (nothing lost)."
  fi
  exit 0
fi

if $HAZARD && ! $FORCE; then
  if [[ ! -t 0 ]]; then
    echo >&2
    die "refusing to discard the above without a TTY to confirm on; pass --force"
  fi
  echo
  printf 'Reset %s to %s, discarding the above? [y/N] ' "$BRANCH" "${TARGET:0:12}"
  # `read` returns non-zero at EOF; under `set -e` that would kill the script
  # with no explanation, so absorb it and fall through to the default (No).
  read -r REPLY || REPLY=""
  case "$REPLY" in
    [yY]|[yY][eE][sS]) ;;
    *) die "aborted; nothing was changed" ;;
  esac
fi

# ── Reset ───────────────────────────────────────────────────────────────

echo
git reset --hard "$TARGET"
echo
echo "Was at $BEFORE (recover with: git reset --hard $BEFORE)"
