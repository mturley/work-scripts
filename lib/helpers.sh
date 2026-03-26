#!/usr/bin/env bash
# helpers.sh - Shared helper functions for worktree scripts

# Base directory for all worktrees. Override with WORKTREES_BASE env var.
WORKTREES_BASE="${WORKTREES_BASE:-$HOME/git/.worktrees}"

prompt_choice() {
  local msg="$1"; shift
  local options=("$@")
  echo "" >&2
  echo "$msg" >&2
  for i in "${!options[@]}"; do
    echo "  $((i+1))) ${options[$i]}" >&2
  done
  while true; do
    printf "Choice [1-%d]: " "${#options[@]}" >&2
    read -r choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
      echo "${options[$((choice-1))]}"
      return
    fi
    echo "Invalid choice, try again." >&2
  done
}

prompt_yn() {
  local msg="$1"
  echo "" >&2
  printf "%s [y/n]: " "$msg" >&2
  while true; do
    read -r yn
    case "$yn" in
      [Yy]*) return 0 ;;
      [Nn]*) return 1 ;;
      *) printf "Please answer y or n: " >&2 ;;
    esac
  done
}

parse_json() {
  python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('$1',''))" 2>/dev/null
}

# resolve_repo_root - Find the project repo to operate on.
# If the current git root contains nested git repos, prompt the user to select one.
# Sets REPO_ROOT to the selected repo's absolute path.
resolve_repo_root() {
  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "ERROR: Not in a git repository. Run this from a git repo or workspace." >&2
    return 1
  fi

  local toplevel
  toplevel="$(git rev-parse --show-toplevel)"

  # Find nested git repos (subdirectories that are their own git roots)
  local repos=()
  while IFS= read -r gitdir; do
    local repo_dir
    repo_dir="$(dirname "$gitdir")"
    # Skip the toplevel itself
    if [ "$repo_dir" != "$toplevel" ]; then
      repos+=("$repo_dir")
    fi
  done < <(find "$toplevel" -maxdepth 4 -name .git -not -path "*/.worktrees/*" -not -path "*/node_modules/*" -not -path "*/.claude/*" 2>/dev/null | sort)

  if [ ${#repos[@]} -eq 0 ]; then
    # No nested repos — use the toplevel as the repo
    REPO_ROOT="$toplevel"
    return 0
  fi

  # Build display names relative to toplevel
  local display_names=()
  for repo in "${repos[@]}"; do
    display_names+=("${repo#"$toplevel"/}")
  done

  if [ ${#repos[@]} -eq 1 ]; then
    echo "Found project repo: ${display_names[0]}"
    REPO_ROOT="${repos[0]}"
    return 0
  fi

  local choice
  choice="$(prompt_choice "Which project repo?" "${display_names[@]}")"
  for i in "${!display_names[@]}"; do
    if [ "${display_names[$i]}" = "$choice" ]; then
      REPO_ROOT="${repos[$i]}"
      return 0
    fi
  done

  echo "ERROR: Could not resolve repo selection." >&2
  return 1
}
