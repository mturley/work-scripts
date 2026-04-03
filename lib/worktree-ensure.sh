#!/usr/bin/env bash
# worktree-ensure.sh - Check if a worktree exists and create it if not
#
# Usage:
#   Branch mode: worktree-ensure.sh branch <worktree-path> <branch-name>
#   PR mode:     worktree-ensure.sh pr <worktree-path> <pr-number> <slug> <base-repo>
#
# Output: JSON object with:
#   status: "created" | "exists" | "exists-elsewhere" | "exists-outdated" | "branch-exists" | "error"
#   path: absolute path to the worktree
#   For "exists-outdated": local_head and remote_head fields
#
# In PR mode, if the worktree doesn't exist, it fetches the PR ref and creates it.
# In branch mode, it fetches upstream/main (or origin/main) and creates a new
# branch based on it. Falls back to reusing an existing branch as-is.

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=helpers.sh
source "$SCRIPTS_DIR/helpers.sh"

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
      if [ -e "$WORKTREE_PATH/.git" ]; then
        json_out "exists" "$WORKTREE_PATH"
        exit 0
      else
        # Directory exists but is not a valid worktree (leftover from a failed operation)
        force_rm "$WORKTREE_PATH"
      fi
    fi

    # Check if branch is already checked out in a different worktree
    EXISTING_WT="$(git worktree list --porcelain | awk -v branch="$BRANCH_NAME" '
      /^worktree / { wt = $0; sub(/^worktree /, "", wt) }
      /^branch refs\/heads\// {
        b = $0; sub(/^branch refs\/heads\//, "", b)
        if (b == branch) { print wt; exit }
      }
    ')"
    if [ -n "$EXISTING_WT" ]; then
      json_out "exists-elsewhere" "$EXISTING_WT"
      exit 0
    fi

    # Fetch upstream main as the base for new branches
    BASE_REF=""
    if git remote get-url upstream &>/dev/null; then
      git fetch upstream main &>/dev/null && BASE_REF="upstream/main"
    elif git remote get-url origin &>/dev/null; then
      git fetch origin main &>/dev/null && BASE_REF="origin/main"
    fi

    # Try creating with new branch first, fall back to existing branch
    if OUTPUT="$(git worktree add "$WORKTREE_PATH" -b "$BRANCH_NAME" ${BASE_REF:+"$BASE_REF"} 2>&1)"; then
      json_out "created" "$(cd "$WORKTREE_PATH" && pwd)"
    elif OUTPUT="$(git worktree add "$WORKTREE_PATH" "$BRANCH_NAME" 2>&1)"; then
      json_out "reused-branch" "$(cd "$WORKTREE_PATH" && pwd)"
    else
      json_out "error" "$WORKTREE_PATH" "message" "$OUTPUT"
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
        if [ -d "$d" ] && [ -e "$d/.git" ]; then
          EXISTING="$d"
          break
        elif [ -d "$d" ]; then
          # Leftover directory, not a valid worktree
          force_rm "$d"
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
    if ! OUTPUT="$(git fetch "https://github.com/${BASE_REPO}.git" "refs/pull/${PR_NUMBER}/head:${BRANCH_NAME}" 2>&1)"; then
      # Check if failure is due to existing branch (non-fast-forward)
      if echo "$OUTPUT" | grep -q 'non-fast-forward' && git rev-parse --verify "$BRANCH_NAME" &>/dev/null; then
        json_out "branch-exists" "$WORKTREE_PATH" "message" "Local branch '${BRANCH_NAME}' already exists (likely leftover from a previous worktree)" "branch" "$BRANCH_NAME"
        exit 0
      fi
      json_out "error" "$WORKTREE_PATH" "message" "$OUTPUT"
      exit 1
    fi
    if ! OUTPUT="$(git worktree add "$WORKTREE_PATH" "$BRANCH_NAME" 2>&1)"; then
      json_out "error" "$WORKTREE_PATH" "message" "$OUTPUT"
      exit 1
    fi
    json_out "created" "$(cd "$WORKTREE_PATH" && pwd)"
    ;;

  *)
    echo "Unknown mode: $MODE. Use 'branch' or 'pr'." >&2
    exit 1
    ;;
esac
