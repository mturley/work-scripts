#!/usr/bin/env bash
#
# pr-ci — check or watch CI status for a GitHub PR.
#
# Usage:
#   pr-ci <pr> [SEC]              Watch CI, polling every SEC seconds (default
#                                 120), alert on first failure or when done
#   pr-ci <pr> --continue-on-fail  Wait for all checks even if some fail
#   pr-ci <pr> --once              Show current CI status summary and exit
#
# <pr> can be a PR number, URL, or branch name — anything `gh pr` accepts.
#

set -euo pipefail

TAB=$'\t'

# ── Usage ───────────────────────────────────────────────────────────────

usage() {
  cat <<'EOF'
Usage: pr-ci <pr> [SECONDS] [--once] [--continue-on-fail] [--ignore-e2e] [--merge]

  <pr>                PR number, URL, or branch name
  [SEC]               Poll interval in seconds (default 120)
  --once              Show current status and exit (no watching)
  --continue-on-fail  Wait for all checks even if some fail
  --ignore-e2e        Don't stop on E2E failures (continue watching)
  --merge             Watch for PR to be merged instead of CI checks

Examples:
  pr-ci 6999                       Watch CI, polling every 120s
  pr-ci 6999 60                    Watch CI, polling every 60s
  pr-ci 6999 --once                Show status once and exit
  pr-ci --once 6999                Flags can come before or after PR
  pr-ci 6999 --continue-on-fail    Wait for all checks to finish
  pr-ci 6999 --ignore-e2e          Watch, but don't stop on E2E failures
  pr-ci --merge 6999               Watch for PR to be merged
  pr-ci https://github.com/org/repo/pull/6999
EOF
  exit 1
}

[[ $# -eq 0 ]] && usage

# Parse arguments in any order
PR=""
WATCH=true
INTERVAL=120
FAIL_FAST=true
IGNORE_E2E=false
WATCH_MERGE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      ;;
    --once)
      WATCH=false
      shift
      ;;
    --continue-on-fail)
      FAIL_FAST=false
      shift
      ;;
    --ignore-e2e)
      IGNORE_E2E=true
      shift
      ;;
    --merge)
      WATCH_MERGE=true
      shift
      ;;
    --*)
      echo "pr-ci: unknown option: $1" >&2
      usage
      ;;
    *)
      # Either a PR identifier or interval (number)
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        INTERVAL="$1"
        shift
      elif [[ -z "$PR" ]]; then
        # First non-flag, non-number argument is the PR
        PR="$1"
        shift
      else
        echo "pr-ci: unexpected argument: $1" >&2
        usage
      fi
      ;;
  esac
done

# Ensure PR was provided
if [[ -z "$PR" ]]; then
  echo "pr-ci: missing PR argument" >&2
  usage
fi

# ── iTerm title ────────────────────────────────────────────────────────

set_iterm_title() {
  if [[ "${TERM_PROGRAM:-}" == "iTerm.app" ]]; then
    # Set session title (tab/window name) using iTerm escape sequence
    printf '\033]1;%s\007' "$1"
  fi
}

# Extract PR number for display (strip URL prefix if present)
PR_DISPLAY="$PR"
case "$PR" in
  *://*)  PR_DISPLAY="${PR##*/}" ;;
esac

# Validate that the PR exists before doing anything else
pr_json=$(gh pr view "$PR" --json title,url 2>&1) || {
  echo "pr-ci: not a valid PR: $PR" >&2
  echo "$pr_json" | head -5 >&2
  exit 1
}
PR_TITLE=$(echo "$pr_json" | jq -r '.title // ""')
PR_URL=$(echo "$pr_json" | jq -r '.url // ""')

set_iterm_title "pr-ci #${PR_DISPLAY}"

# ── Helpers ─────────────────────────────────────────────────────────────

get_checks() {
  # Use JSON output to deduplicate: when a check has multiple runs, keep
  # only the latest (by startedAt).  The "bucket" field gives the same
  # pass/fail/pending/skipping values as the plain-text output.
  gh pr checks "$PR" --json name,bucket,startedAt,link \
    --jq '
      group_by(.name) | map(sort_by(.startedAt) | last) |
      map(.name + "\t" + .bucket + "\t\t" + (.link // "")) | .[]
    ' 2>&1 || true
}

count_status() {
  local output="$1" status="$2"
  echo "$output" | grep -c "${TAB}${status}${TAB}" || true
}

only_pending_is_tide() {
  local output="$1"
  local pending_lines
  pending_lines=$(echo "$output" | grep "${TAB}pending${TAB}" || true)
  [[ -n "$pending_lines" ]] && \
    [[ $(echo "$pending_lines" | wc -l) -eq 1 ]] && \
    echo "$pending_lines" | grep -q "^tide${TAB}"
}

summarize() {
  local output="$1"
  local passed failed pending skipping
  passed=$(count_status "$output" "pass")
  failed=$(count_status "$output" "fail")
  pending=$(count_status "$output" "pending")
  skipping=$(count_status "$output" "skipping")

  echo "Passed: $passed  Failed: $failed  Pending: $pending  Skipped: $skipping"

  if [[ "$failed" -gt 0 ]]; then
    echo ""
    echo "Failed checks:"
    echo "$output" | grep "${TAB}fail${TAB}" | awk -F'\t' '{print "  ✗ " $1}' || true
  fi

  if [[ "$pending" -gt 0 ]]; then
    if only_pending_is_tide "$output"; then
      echo ""
      echo "Pending: tide (requires approval — ignored)"
    else
      echo ""
      echo "Pending checks:"
      echo "$output" | grep "${TAB}pending${TAB}" | awk -F'\t' '{print "  ⏳ " $1}' || true
    fi
  fi
}

is_done() {
  local output="$1"
  local pending
  pending=$(count_status "$output" "pending")
  [[ "$pending" -eq 0 ]] || only_pending_is_tide "$output"
}

has_failures() {
  local output="$1"
  local failed_output
  failed_output=$(echo "$output" | grep "${TAB}fail${TAB}" || true)

  # If --ignore-e2e is set, filter out E2E failures
  if $IGNORE_E2E; then
    failed_output=$(echo "$failed_output" | grep -v "^Cypress E2E Tests${TAB}" || true)
  fi

  [[ -n "$failed_output" ]]
}

alert() {
  local title="$1"
  local body="$2"
  osascript -e "display alert \"$title\" message \"$body\" buttons {\"OK\"} default button \"OK\"" 2>/dev/null || true
}

# ── Main: merge watch mode ─────────────────────────────────────────────

if $WATCH_MERGE; then
  # Get initial merge state
  merge_state=$(gh pr view "$PR" --json state,mergedAt --jq '{state: .state, mergedAt: .mergedAt}')
  state=$(echo "$merge_state" | jq -r '.state')
  merged_at=$(echo "$merge_state" | jq -r '.mergedAt')

  if [[ -n "$PR_TITLE" ]]; then
    echo "PR #${PR_DISPLAY}: ${PR_TITLE}"
  else
    echo "PR $PR"
  fi
  echo ""
  echo "Merge Status"
  echo "─────────────────────────────────"
  echo "State: $state"
  if [[ -n "$PR_URL" ]]; then
    echo ""
    echo "$PR_URL"
  fi

  if [[ "$state" == "MERGED" ]]; then
    echo ""
    echo "PR already merged at: $merged_at"
    exit 0
  fi

  if ! $WATCH; then
    exit 0
  fi

  echo ""
  echo "Watching for merge every ${INTERVAL}s… (Ctrl-C to stop)"
  echo ""

  while true; do
    sleep "$INTERVAL"
    set_iterm_title "pr-ci #${PR_DISPLAY}"
    merge_state=$(gh pr view "$PR" --json state,mergedAt --jq '{state: .state, mergedAt: .mergedAt}')
    state=$(echo "$merge_state" | jq -r '.state')
    merged_at=$(echo "$merge_state" | jq -r '.mergedAt')
    timestamp=$(date '+%H:%M:%S')

    if [[ "$state" == "MERGED" ]]; then
      echo "[$timestamp] PR merged!"
      echo ""
      if [[ -n "$PR_TITLE" ]]; then
        echo "PR #${PR_DISPLAY}: ${PR_TITLE}"
        echo ""
      fi
      echo "Merged at: $merged_at"
      if [[ -n "$PR_URL" ]]; then
        echo ""
        echo "$PR_URL"
      fi
      alert "PR #${PR_DISPLAY} — Merged" "${PR_TITLE:+${PR_TITLE} — }PR has been merged!"
      exit 0
    fi

    echo "[$timestamp] State: $state"
  done
fi

# ── Main: one-shot ──────────────────────────────────────────────────────

output=$(get_checks)
if [[ -n "$PR_TITLE" ]]; then
  echo "PR #${PR_DISPLAY}: ${PR_TITLE}"
else
  echo "PR $PR"
fi
echo ""
echo "CI Status"
echo "─────────────────────────────────"
summarize "$output"
if [[ -n "$PR_URL" ]]; then
  echo ""
  echo "$PR_URL"
fi

if ! $WATCH; then
  exit 0
fi

# ── Main: watch mode ────────────────────────────────────────────────────

report_and_alert() {
  local label="$1"
  local output="$2"

  echo ""
  if [[ -n "$PR_TITLE" ]]; then
    echo "PR #${PR_DISPLAY}: ${PR_TITLE}"
    echo ""
  fi
  summarize "$output"
  if [[ -n "$PR_URL" ]]; then
    echo ""
    echo "$PR_URL"
  fi

  # Build alert message
  local passed failed skipping
  passed=$(count_status "$output" "pass")
  failed=$(count_status "$output" "fail")
  skipping=$(count_status "$output" "skipping")
  if [[ "$failed" -gt 0 ]]; then
    failed_names=$(echo "$output" | grep "${TAB}fail${TAB}" | awk -F'\t' '{print $1}' | paste -sd', ' -)
    alert "PR #${PR_DISPLAY} — ${label}" "${PR_TITLE:+${PR_TITLE} — }Passed: $passed, Failed: $failed, Skipped: $skipping -- Failed: $failed_names"
  else
    alert "PR #${PR_DISPLAY} — ${label}" "${PR_TITLE:+${PR_TITLE} — }All $passed checks passed! ($skipping skipped)"
  fi
}

should_stop() {
  local output="$1"
  is_done "$output" && return 0
  $FAIL_FAST && has_failures "$output" && return 0
  return 1
}

if should_stop "$output"; then
  echo ""
  if is_done "$output"; then
    echo "All checks already complete."
  else
    echo "Failure detected."
  fi
  exit 0
fi

echo ""
echo "Watching every ${INTERVAL}s… (Ctrl-C to stop)"
echo ""

while true; do
  sleep "$INTERVAL"
  set_iterm_title "pr-ci #${PR_DISPLAY}"
  output=$(get_checks)
  timestamp=$(date '+%H:%M:%S')

  if should_stop "$output"; then
    if is_done "$output"; then
      echo "[$timestamp] All checks complete!"
    else
      echo "[$timestamp] Failure detected — stopping early."
    fi
    report_and_alert "CI Complete" "$output"
    exit 0
  fi

  pending=$(count_status "$output" "pending")
  passed=$(count_status "$output" "pass")
  failed=$(count_status "$output" "fail")
  echo "[$timestamp] Pending: $pending  Passed: $passed  Failed: $failed"
done
