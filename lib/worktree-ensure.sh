#!/usr/bin/env bash
# worktree-ensure.sh - Check if a worktree exists and create it if not
#
# Usage:
#   Branch mode: worktree-ensure.sh branch <worktree-path> <branch-name>
#   PR mode:     worktree-ensure.sh pr <worktree-path> <pr-number> <slug> <base-repo>
#
# Output: JSON object with:
#   status: "created" | "exists" | "exists-outdated"
#   path: absolute path to the worktree
#   For "exists-outdated": local_head and remote_head fields
#
# In PR mode, if the worktree doesn't exist, it fetches the PR ref and creates it.
# In branch mode, it tries `git worktree add <path> -b <branch>`, falling back to
# `git worktree add <path> <branch>` if the branch already exists.

set -euo pipefail

MODE="${1:?Usage: worktree-ensure.sh <branch|pr> ...}"
WORKTREE_PATH="${2:?Missing worktree path}"

json_out() {
  # Simple JSON output helper
  local status="$1" path="$2"
  shift 2
  local extra=""
  while [ $# -ge 2 ]; do
    extra="$extra, \"$1\": \"$2\""
    shift 2
  done
  echo "{\"status\": \"$status\", \"path\": \"$path\"$extra}"
}

case "$MODE" in
  branch)
    BRANCH_NAME="${3:?Missing branch name}"

    if [ -d "$WORKTREE_PATH" ]; then
      json_out "exists" "$WORKTREE_PATH"
      exit 0
    fi

    # Try creating with new branch first, fall back to existing branch
    if git worktree add "$WORKTREE_PATH" -b "$BRANCH_NAME" 2>/dev/null; then
      json_out "created" "$(cd "$WORKTREE_PATH" && pwd)"
    elif git worktree add "$WORKTREE_PATH" "$BRANCH_NAME" 2>&1; then
      json_out "created" "$(cd "$WORKTREE_PATH" && pwd)"
    else
      echo '{"status": "error", "message": "Failed to create worktree"}' >&2
      exit 1
    fi
    ;;

  pr)
    PR_NUMBER="${3:?Missing PR number}"
    SLUG="${4:?Missing slug}"
    BASE_REPO="${5:?Missing base repo (owner/repo)}"

    # Check for existing worktree matching this PR number (glob on *--pr-<number>-*)
    WORKTREE_DIR="$(dirname "$WORKTREE_PATH")"
    EXISTING=""
    if [ -d "$WORKTREE_DIR" ]; then
      for d in "$WORKTREE_DIR"/*--pr-"${PR_NUMBER}"-*; do
        if [ -d "$d" ]; then
          EXISTING="$d"
          break
        fi
      done
    fi

    if [ -n "$EXISTING" ]; then
      # Fetch latest PR ref and compare
      git fetch "https://github.com/${BASE_REPO}.git" "refs/pull/${PR_NUMBER}/head" 2>/dev/null
      REMOTE_HEAD="$(git rev-parse FETCH_HEAD)"
      LOCAL_HEAD="$(git -C "$EXISTING" rev-parse HEAD)"

      if [ "$REMOTE_HEAD" = "$LOCAL_HEAD" ]; then
        json_out "exists" "$EXISTING"
      else
        json_out "exists-outdated" "$EXISTING" "local_head" "$LOCAL_HEAD" "remote_head" "$REMOTE_HEAD"
      fi
      exit 0
    fi

    # Create new worktree for PR
    BRANCH_NAME="review/pr-${PR_NUMBER}-${SLUG}"
    git fetch "https://github.com/${BASE_REPO}.git" "refs/pull/${PR_NUMBER}/head:${BRANCH_NAME}" 2>&1
    git worktree add "$WORKTREE_PATH" "$BRANCH_NAME" 2>&1
    json_out "created" "$(cd "$WORKTREE_PATH" && pwd)"
    ;;

  *)
    echo "Unknown mode: $MODE. Use 'branch' or 'pr'." >&2
    exit 1
    ;;
esac
