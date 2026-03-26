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

# prompt_multi_select "message" option1 option2 ...
# User enters comma-separated numbers or ranges (e.g. "1,3-5"), or "a" for all, or "n" for none.
# Selected options are printed to stdout, one per line.
prompt_multi_select() {
  local msg="$1"; shift
  local options=("$@")
  echo "" >&2
  echo "$msg" >&2
  for i in "${!options[@]}"; do
    echo "  $((i+1))) ${options[$i]}" >&2
  done
  while true; do
    printf "Select [1-%d, comma/range, a=all, n=none]: " "${#options[@]}" >&2
    read -r input
    if [[ "$input" == "n" || "$input" == "N" ]]; then
      return
    fi
    if [[ "$input" == "a" || "$input" == "A" ]]; then
      printf '%s\n' "${options[@]}"
      return
    fi
    # Parse comma-separated numbers and ranges
    local valid=true
    local selected=()
    IFS=',' read -ra parts <<< "$input"
    for part in "${parts[@]}"; do
      part="$(echo "$part" | tr -d ' ')"
      if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        local start="${BASH_REMATCH[1]}" end="${BASH_REMATCH[2]}"
        if [ "$start" -ge 1 ] && [ "$end" -le "${#options[@]}" ] && [ "$start" -le "$end" ]; then
          for ((j=start; j<=end; j++)); do
            selected+=("${options[$((j-1))]}")
          done
        else
          valid=false
        fi
      elif [[ "$part" =~ ^[0-9]+$ ]] && [ "$part" -ge 1 ] && [ "$part" -le "${#options[@]}" ]; then
        selected+=("${options[$((part-1))]}")
      else
        valid=false
      fi
    done
    if $valid && [ ${#selected[@]} -gt 0 ]; then
      printf '%s\n' "${selected[@]}"
      return
    fi
    echo "Invalid selection, try again." >&2
  done
}

# remove_worktree <path> - Remove a worktree, handling invalid/leftover directories
remove_worktree() {
  local wt_path="$1"
  if git worktree remove "$wt_path" --force 2>/dev/null; then
    return 0
  fi
  # Fallback: directory exists but isn't a valid worktree
  if [ -d "$wt_path" ]; then
    rm -rf "$wt_path"
    git worktree prune 2>/dev/null
  fi
}

# copy_worktree_files <scripts-dir> <repo-root> <worktree-path>
# Finds copyable files, prompts user to select (with caching), and copies.
# Returns 0 if files were copied, 1 otherwise.
copy_worktree_files() {
  local scripts_dir="$1" repo_root="$2" wt_path="$3"
  local repo_name
  repo_name="$(basename "$repo_root")"
  local cache_file="/tmp/worktree-copy-selection-${repo_name}"

  echo "Checking for copyable files (node_modules, build outputs, config)..."
  local dir_targets dotfile_targets
  dir_targets="$("$scripts_dir/copy-worktree-files.sh" --list-dirs "$repo_root")"
  dotfile_targets="$("$scripts_dir/copy-worktree-files.sh" --list-dotfiles "$repo_root")"

  local options=()
  if [ -n "$dir_targets" ]; then
    while IFS= read -r line; do options+=("$line"); done <<< "$dir_targets"
  fi
  if [ -n "$dotfile_targets" ]; then
    options+=("Top-level dotfiles")
  fi

  if [ ${#options[@]} -eq 0 ]; then
    return 1
  fi

  local selected=()

  # Check for cached selection
  if [ -f "$cache_file" ]; then
    local cached
    cached="$(cat "$cache_file")"
    # Verify all cached options are still available
    local all_valid=true
    while IFS= read -r item; do
      local found=false
      for opt in "${options[@]}"; do
        if [ "$opt" = "$item" ]; then found=true; break; fi
      done
      if ! $found; then all_valid=false; break; fi
    done <<< "$cached"

    if $all_valid && [ -n "$cached" ]; then
      echo ""
      echo "Previous selection for ${repo_name}:"
      while IFS= read -r item; do echo "  - $item"; done <<< "$cached"
      if prompt_yn "Use this selection?"; then
        while IFS= read -r line; do [ -n "$line" ] && selected+=("$line"); done <<< "$cached"
      fi
    fi
  fi

  # If no cached selection was used, prompt
  if [ ${#selected[@]} -eq 0 ]; then
    while IFS= read -r line; do [ -n "$line" ] && selected+=("$line"); done < <(prompt_multi_select "Which files to copy to the new worktree?" "${options[@]}")
    # Save selection
    if [ ${#selected[@]} -gt 0 ]; then
      printf '%s\n' "${selected[@]}" > "$cache_file"
    fi
  fi

  if [ ${#selected[@]} -eq 0 ]; then
    return 1
  fi

  # Expand "Top-level dotfiles" into individual paths
  local copy_paths=()
  for item in "${selected[@]}"; do
    if [ "$item" = "Top-level dotfiles" ]; then
      while IFS= read -r df; do copy_paths+=("$df"); done <<< "$dotfile_targets"
    else
      copy_paths+=("$item")
    fi
  done

  if [ ${#copy_paths[@]} -gt 0 ]; then
    "$scripts_dir/copy-worktree-files.sh" --copy "$repo_root" "$wt_path" "${copy_paths[@]}"
    return 0
  fi
  return 1
}

# warn_unmerged_commits <branch-name>
# Checks if the branch has commits not on upstream/main (or origin/main).
# Prints a warning and prompts for confirmation. Returns 1 if user aborts.
warn_unmerged_commits() {
  local branch="$1"
  # Find the base ref
  local base_ref=""
  if git rev-parse --verify upstream/main &>/dev/null; then
    base_ref="upstream/main"
  elif git rev-parse --verify origin/main &>/dev/null; then
    base_ref="origin/main"
  fi
  if [ -z "$base_ref" ]; then
    return 0
  fi
  # Check if branch exists
  if ! git rev-parse --verify "$branch" &>/dev/null; then
    return 0
  fi
  local unmerged
  unmerged="$(git log --oneline "$base_ref".."$branch" 2>/dev/null)"
  if [ -n "$unmerged" ]; then
    echo ""
    echo "WARNING: Branch '${branch}' has unmerged commits:"
    echo "$unmerged"
    if ! prompt_yn "Delete this branch and start fresh?"; then
      return 1
    fi
  fi
  return 0
}

# recreate_worktree <scripts-dir> <worktree-abs> <branch-name> <wt-path>
# Removes the worktree and branch, then recreates both from upstream/main.
# Sets WT_PATH to the new worktree path. Returns 1 if user aborts.
recreate_worktree() {
  local scripts_dir="$1" worktree_abs="$2" branch_name="$3" wt_path="$4"
  warn_unmerged_commits "$branch_name" || return 1
  remove_worktree "$wt_path"
  # Delete the branch so worktree-ensure creates it fresh from upstream/main
  git branch -D "$branch_name" 2>/dev/null || true
  if ! RESULT="$("$scripts_dir/worktree-ensure.sh" branch "$worktree_abs" "$branch_name" 2>&1)"; then
    local msg
    msg="$(echo "$RESULT" | parse_json message)"
    echo "ERROR: Failed to recreate worktree." >&2
    [ -n "$msg" ] && echo "  $msg" >&2
    return 1
  fi
  WT_PATH="$(echo "$RESULT" | parse_json path)"
  echo "Worktree recreated at: ${WT_PATH}"
  return 0
}

# detect_editor - Sets EDITOR_CMD to "cursor" or "code" if detected, empty otherwise.
detect_editor() {
  EDITOR_CMD=""
  if [ -n "${CURSOR_CHANNEL:-}" ] || [[ "${__CFBundleIdentifier:-}" == *cursor* ]]; then
    EDITOR_CMD="cursor"
  elif [ -n "${VSCODE_PID:-}" ] || [ "${TERM_PROGRAM:-}" = "vscode" ]; then
    EDITOR_CMD="code"
  fi
}

# open_editor <worktree-path> - Open the worktree in an editor.
# Uses EDITOR_CMD if set, otherwise prompts the user to choose.
open_editor() {
  local wt_path="$1"
  if [ -n "${EDITOR_CMD:-}" ]; then
    env -u CLAUDECODE $EDITOR_CMD --new-window "$wt_path"
    echo "Opened new ${EDITOR_CMD} window."
  else
    echo "No editor detected."
    if prompt_yn "Would you like to open an editor?"; then
      local choice
      choice="$(prompt_choice "Which editor?" "VS Code" "Cursor")"
      case "$choice" in
        "VS Code") env -u CLAUDECODE code --new-window "$wt_path" ;;
        "Cursor") env -u CLAUDECODE cursor --new-window "$wt_path" ;;
      esac
    fi
  fi
}

# worktree_repl <repo-root> <worktree-path>
# Interactive loop offering cleanup, open, status, and exit commands.
worktree_repl() {
  local repo_root="$1" wt_path="$2"
  echo ""
  echo "Commands: open, status, cleanup, exit"
  while true; do
    printf "\nworktree> "
    read -r cmd
    case "$cmd" in
      open)
        open_editor "$wt_path"
        ;;
      status)
        git -C "$wt_path" status
        ;;
      cleanup)
        echo "This will remove the worktree at:"
        echo "  $wt_path"
        if prompt_yn "Proceed?"; then
          remove_worktree "$wt_path"
          echo "Worktree removed."
          # Also clean up the branch if it was created for this worktree
          git worktree prune 2>/dev/null
          exit 0
        fi
        ;;
      exit|quit|q)
        exit 0
        ;;
      "")
        ;;
      *)
        echo "Unknown command: $cmd"
        echo "Commands: open, status, cleanup, exit"
        ;;
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
