#!/usr/bin/env bash
#
# dev-ports — find dev servers running in git repositories.
#
# Lists all listening TCP ports whose process is running in a git repo,
# grouped by repo and branch/worktree.
#
# Usage: dev-ports
#

set -euo pipefail

MAX_CMD_LEN=40

# ── Collect listener data ───────────────────────────────────────────────

# Each entry in these parallel arrays represents one listener.
# We use parallel arrays because bash 3.2 has no associative arrays.
entry_repo_root=()    # absolute path to repo root (from --git-common-dir)
entry_repo_name=()    # basename of repo root
entry_worktree=()     # absolute path to worktree (from --show-toplevel)
entry_branch=()       # branch name or "(detached)"
entry_port=()         # port number
entry_cmd=()          # process command (truncated)
entry_pid=()          # process ID

# Cache: avoid re-resolving the same PID's cwd/git info
declare -a seen_pids=()
declare -a seen_pid_repo_root=()
declare -a seen_pid_repo_name=()
declare -a seen_pid_worktree=()
declare -a seen_pid_branch=()
declare -a seen_pid_cmd=()
declare -a seen_pid_valid=()  # "yes" or "no"

lookup_pid_cache() {
  local pid="$1"
  local i
  for i in "${!seen_pids[@]}"; do
    if [[ "${seen_pids[$i]}" == "$pid" ]]; then
      echo "$i"
      return 0
    fi
  done
  return 1
}

resolve_pid() {
  local pid="$1"

  local cwd
  cwd=$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | grep '^n/' | sed 's/^n//') || true
  if [[ -z "$cwd" ]]; then
    seen_pids+=("$pid")
    seen_pid_valid+=("no")
    seen_pid_repo_root+=("")
    seen_pid_repo_name+=("")
    seen_pid_worktree+=("")
    seen_pid_branch+=("")
    seen_pid_cmd+=("")
    return 1
  fi

  local toplevel
  toplevel=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || true
  if [[ -z "$toplevel" ]]; then
    seen_pids+=("$pid")
    seen_pid_valid+=("no")
    seen_pid_repo_root+=("")
    seen_pid_repo_name+=("")
    seen_pid_worktree+=("")
    seen_pid_branch+=("")
    seen_pid_cmd+=("")
    return 1
  fi

  local git_common_dir
  git_common_dir=$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || true
  # Strip trailing /.git to get the repo root
  local repo_root="${git_common_dir%/.git}"

  local repo_name
  repo_name=$(basename "$repo_root")

  local branch
  branch=$(git -C "$cwd" branch --show-current 2>/dev/null) || true
  if [[ -z "$branch" ]]; then
    branch="(detached)"
  fi

  local cmd
  cmd=$(ps -ww -o args= -p "$pid" 2>/dev/null) || true
  cmd="${cmd//$HOME/~}"
  if [[ ${#cmd} -gt $MAX_CMD_LEN ]]; then
    local half=$(( (MAX_CMD_LEN - 3) / 2 ))
    cmd="${cmd:0:$half}...${cmd: -$half}"
  fi

  seen_pids+=("$pid")
  seen_pid_valid+=("yes")
  seen_pid_repo_root+=("$repo_root")
  seen_pid_repo_name+=("$repo_name")
  seen_pid_worktree+=("$toplevel")
  seen_pid_branch+=("$branch")
  seen_pid_cmd+=("$cmd")
  return 0
}

# Parse lsof output for all TCP listeners
while IFS= read -r line; do
  # Skip the header line
  [[ "$line" == COMMAND* ]] && continue

  # Extract PID (field 2) and NAME (second-to-last field, contains host:port)
  # The last field is "(LISTEN)", so NAME is $(NF-1)
  local_pid=$(echo "$line" | awk '{print $2}')
  local_name=$(echo "$line" | awk '{print $(NF-1)}')

  # Extract port from NAME (format is "host:port" or "*:port")
  local_port="${local_name##*:}"

  # Check cache first
  cache_idx=""
  if cache_idx=$(lookup_pid_cache "$local_pid"); then
    if [[ "${seen_pid_valid[$cache_idx]}" == "no" ]]; then
      continue
    fi
    entry_repo_root+=("${seen_pid_repo_root[$cache_idx]}")
    entry_repo_name+=("${seen_pid_repo_name[$cache_idx]}")
    entry_worktree+=("${seen_pid_worktree[$cache_idx]}")
    entry_branch+=("${seen_pid_branch[$cache_idx]}")
    entry_port+=("$local_port")
    entry_cmd+=("${seen_pid_cmd[$cache_idx]}")
    entry_pid+=("$local_pid")
    continue
  fi

  # Resolve PID info (populates cache)
  if ! resolve_pid "$local_pid"; then
    continue
  fi

  # Get the index of the just-added cache entry
  cache_idx=$(( ${#seen_pids[@]} - 1 ))
  entry_repo_root+=("${seen_pid_repo_root[$cache_idx]}")
  entry_repo_name+=("${seen_pid_repo_name[$cache_idx]}")
  entry_worktree+=("${seen_pid_worktree[$cache_idx]}")
  entry_branch+=("${seen_pid_branch[$cache_idx]}")
  entry_port+=("$local_port")
  entry_cmd+=("${seen_pid_cmd[$cache_idx]}")
  entry_pid+=("$local_pid")

done < <(lsof -iTCP -sTCP:LISTEN -nP 2>/dev/null)

# ── Check for results ───────────────────────────────────────────────────

if [[ ${#entry_port[@]} -eq 0 ]]; then
  echo "No dev servers found in git repositories."
  exit 0
fi

# ── Sort and group output ───────────────────────────────────────────────

tilde_path() {
  echo "${1/#$HOME/~}"
}

# Build sort keys: "repo_name|repo_root|branch|worktree|port|cmd|pid"
# Then sort and iterate to produce grouped output.
sort_lines=""
for i in "${!entry_port[@]}"; do
  sort_lines+="${entry_repo_name[$i]}|${entry_repo_root[$i]}|${entry_branch[$i]}|${entry_worktree[$i]}|${entry_port[$i]}|${entry_cmd[$i]}|${entry_pid[$i]}"
  sort_lines+=$'\n'
done

prev_repo=""
prev_branch_wt=""

while IFS='|' read -r repo_name repo_root branch worktree port cmd pid; do
  [[ -z "$repo_name" ]] && continue

  # Repo header
  if [[ "$repo_root" != "$prev_repo" ]]; then
    # Blank line between repos (but not before the first)
    [[ -n "$prev_repo" ]] && echo
    echo "$repo_name ($(tilde_path "$repo_root"))"
    prev_repo="$repo_root"
    prev_branch_wt=""
  fi

  # Branch line
  branch_wt_key="${branch}|${worktree}"
  if [[ "$branch_wt_key" != "$prev_branch_wt" ]]; then
    if [[ "$worktree" == "$repo_root" ]]; then
      echo "  $branch"
    else
      echo "  $branch ($(tilde_path "$worktree"))"
    fi
    prev_branch_wt="$branch_wt_key"
  fi

  # Port line
  echo "    :${port}  ${cmd} (pid ${pid})"

done < <(echo "$sort_lines" | sort -t'|' -k1,1f -k3,3f -k5,5n)
