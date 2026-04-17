#!/usr/bin/env bash
# helpers.sh - Shared helper functions for worktree scripts

# Base directory for all worktrees. Override with WORKTREES_BASE env var.
WORKTREES_BASE="${WORKTREES_BASE:-$HOME/git/.worktrees}"

# Port range configuration
PORT_RANGE_FILE="${WORKTREES_BASE}/.port-ranges"
PORT_RANGE_SIZE=10
PORT_RANGE_BASE=4020  # First worktree starts here (4010-4019 is the default for main checkout)

# assign_port_range <worktree-name>
# Assigns a port range for the given worktree. Prints the range string (e.g. "4020-4029").
# If the worktree already has an assignment, returns that.
# Otherwise assigns the lowest available slot.
assign_port_range() {
  local wt_name="$1"
  mkdir -p "$WORKTREES_BASE"
  touch "$PORT_RANGE_FILE"

  # Check if already assigned
  local existing
  existing=$(awk -v name="$wt_name" '$2 == name {print $1; exit}' "$PORT_RANGE_FILE")
  if [ -n "$existing" ]; then
    local start=$((PORT_RANGE_BASE + existing * PORT_RANGE_SIZE))
    echo "${start}-$((start + PORT_RANGE_SIZE - 1))"
    return
  fi

  # Find lowest available slot (0, 1, 2, ...)
  local used_slots slot=0
  used_slots=$(awk '{print $1}' "$PORT_RANGE_FILE" | sort -n)
  for used in $used_slots; do
    if [ "$slot" -eq "$used" ]; then
      slot=$((slot + 1))
    fi
  done

  echo "$slot $wt_name" >> "$PORT_RANGE_FILE"
  local start=$((PORT_RANGE_BASE + slot * PORT_RANGE_SIZE))
  echo "${start}-$((start + PORT_RANGE_SIZE - 1))"
}

# release_port_range <worktree-name>
# Releases the port range for a worktree being cleaned up.
release_port_range() {
  local wt_name="$1"
  if [ -f "$PORT_RANGE_FILE" ]; then
    local tmp="${PORT_RANGE_FILE}.tmp"
    grep -v " ${wt_name}$" "$PORT_RANGE_FILE" > "$tmp" 2>/dev/null || true
    mv "$tmp" "$PORT_RANGE_FILE"
  fi
}

# Terminal colors
COLOR_BLUE="$(tput setaf 12 2>/dev/null || true)"
COLOR_CYAN="$(tput setaf 6 2>/dev/null || true)"
COLOR_GREEN="$(tput setaf 2 2>/dev/null || true)"
COLOR_RED="$(tput setaf 1 2>/dev/null || true)"
COLOR_YELLOW="$(tput setaf 3 2>/dev/null || true)"
COLOR_DIM="$(tput dim 2>/dev/null || true)"
COLOR_RESET="$(tput sgr0 2>/dev/null || true)"

# short_path <path> - Replace $HOME prefix with ~
short_path() {
  echo "${1/#$HOME/~}"
}

# relative_time <iso8601-timestamp> - Convert ISO 8601 timestamp to relative time
relative_time() {
  local timestamp="$1"
  if [ -z "$timestamp" ]; then
    echo ""
    return
  fi

  # Convert ISO 8601 to epoch seconds (works on both macOS and Linux)
  local epoch
  if date -j -f "%Y-%m-%dT%H:%M:%SZ" "${timestamp%.*}Z" "+%s" &>/dev/null; then
    # macOS (BSD date)
    epoch="$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "${timestamp%.*}Z" "+%s" 2>/dev/null || echo "")"
  else
    # Linux (GNU date)
    epoch="$(date -d "$timestamp" "+%s" 2>/dev/null || echo "")"
  fi

  if [ -z "$epoch" ]; then
    echo "$timestamp"
    return
  fi

  local now
  now="$(date "+%s")"
  local diff=$((now - epoch))

  if [ $diff -lt 60 ]; then
    echo "just now"
  elif [ $diff -lt 3600 ]; then
    local mins=$((diff / 60))
    if [ $mins -eq 1 ]; then
      echo "1 minute ago"
    else
      echo "${mins} minutes ago"
    fi
  elif [ $diff -lt 86400 ]; then
    local hours=$((diff / 3600))
    if [ $hours -eq 1 ]; then
      echo "1 hour ago"
    else
      echo "${hours} hours ago"
    fi
  elif [ $diff -lt 2592000 ]; then
    local days=$((diff / 86400))
    if [ $days -eq 1 ]; then
      echo "1 day ago"
    else
      echo "${days} days ago"
    fi
  elif [ $diff -lt 31536000 ]; then
    local months=$((diff / 2592000))
    if [ $months -eq 1 ]; then
      echo "1 month ago"
    else
      echo "${months} months ago"
    fi
  else
    local years=$((diff / 31536000))
    if [ $years -eq 1 ]; then
      echo "1 year ago"
    else
      echo "${years} years ago"
    fi
  fi
}

prompt_choice() {
  local msg="$1"; shift
  local options=("$@")
  echo "" >&2
  echo "$msg" >&2
  for i in "${!options[@]}"; do
    echo "  ${COLOR_BLUE}$((i+1)))${COLOR_RESET} ${options[$i]}" >&2
  done
  while true; do
    printf "Choice [${COLOR_BLUE}1-%d${COLOR_RESET}]: " "${#options[@]}" >&2
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
  printf "%s [${COLOR_BLUE}y${COLOR_RESET}/${COLOR_BLUE}n${COLOR_RESET}]: " "$msg" >&2
  while true; do
    read -r yn
    case "$yn" in
      [Yy]*) return 0 ;;
      [Nn]*) return 1 ;;
      *) printf "Please answer ${COLOR_BLUE}y${COLOR_RESET} or ${COLOR_BLUE}n${COLOR_RESET}: " >&2 ;;
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
    echo "  ${COLOR_BLUE}$((i+1)))${COLOR_RESET} ${options[$i]}" >&2
  done
  while true; do
    printf "Select [${COLOR_BLUE}1-%d${COLOR_RESET}, comma/range, ${COLOR_BLUE}a${COLOR_RESET}=all, ${COLOR_BLUE}n${COLOR_RESET}=none]: " "${#options[@]}" >&2
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

# spin_wait <pid> <message> - Show a spinner while a background process runs
spin_wait() {
  local pid="$1" msg="$2"
  local spin_chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r  %s %s" "${spin_chars:$((i % ${#spin_chars})):1}" "$msg" >&2
    i=$((i + 1))
    sleep 0.1
  done
  printf "\r%*s\r" $((${#msg} + 4)) "" >&2
  wait "$pid"
  return $?
}

# force_rm <path> - Remove a directory, fixing permissions first to avoid errors
force_rm() {
  local target="$1"
  echo "Removing $(basename "$target")..."
  chmod -R u+rwx "$target" 2>/dev/null || true
  local exit_code=0
  rm -rf "$target" &
  spin_wait $! "deleting files..." || exit_code=$?
  if [ $exit_code -eq 0 ] && [ ! -d "$target" ]; then
    return 0
  fi
  # Removal failed
  echo "ERROR: Failed to remove $target" >&2
  echo "  $err" >&2
  return 1
}

# remove_worktree <path> - Remove a worktree, handling invalid/leftover directories
remove_worktree() {
  local wt_path="$1"
  echo "Removing worktree at $(basename "$wt_path")..."
  # Derive the main repo root from the worktree so git commands work
  # regardless of the caller's working directory
  local repo_root=""
  if [ -e "$wt_path/.git" ]; then
    repo_root="$(git -C "$wt_path" worktree list --porcelain 2>/dev/null | head -1 | sed 's/^worktree //')"
  fi
  if [ -n "$repo_root" ]; then
    git -C "$repo_root" worktree remove "$wt_path" --force &>/dev/null &
    if spin_wait $! "removing worktree..." && [ ! -d "$wt_path" ]; then
      echo "Pruning worktree list..."
      git -C "$repo_root" worktree prune 2>/dev/null
      return 0
    fi
  fi
  # Fallback: directory exists but isn't a valid worktree
  if [ -d "$wt_path" ]; then
    force_rm "$wt_path"
    if [ -n "$repo_root" ]; then
      echo "Pruning worktree list..."
      git -C "$repo_root" worktree prune 2>/dev/null
    fi
  fi
}


# clone_worktree_files <scripts-dir> <repo-root> <worktree-path>
# Prompts the user to clone gitignored files from the main clone into a new
# worktree. On macOS, uses APFS copy-on-write clones (cp -Rc). On other
# platforms, symlinks most files but copies node_modules via rsync.
# Dotfile and dir selections are cached separately in /tmp.
# Returns 0 if files were cloned, 1 otherwise.
clone_worktree_files() {
  local scripts_dir="$1" repo_root="$2" wt_path="$3"
  local repo_name
  repo_name="$(basename "$repo_root")"
  local cache_dotfiles="/tmp/worktree-clone-dotfiles-${repo_name}"
  local cache_dirs="/tmp/worktree-clone-dirs-${repo_name}"

  # --- Initial prompt: what level of cloning/linking? ---
  local is_mac=false
  [ "$(uname -s)" = "Darwin" ] && is_mac=true

  echo ""
  if $is_mac; then
    echo "Do you want to clone some gitignored files from the root repo"
    echo "to simplify running the dev environment in the worktree?"
    echo "${COLOR_DIM}(Uses APFS copy-on-write clones.)${COLOR_RESET}"
    echo ""
    echo "  ${COLOR_BLUE}1)${COLOR_RESET} Clone configuration (top-level dotfiles), dependencies and build artifacts"
    echo "  ${COLOR_BLUE}2)${COLOR_RESET} Clone top-level configuration (dotfiles) only (you'll need to install/build yourself)"
    echo "  ${COLOR_BLUE}3)${COLOR_RESET} Don't clone anything"
  else
    echo "Do you want to copy some gitignored files from the root repo"
    echo "to simplify running the dev environment in the worktree?"
    echo "${COLOR_DIM}(Uses rsync — full independent copies.)${COLOR_RESET}"
    echo ""
    echo "  ${COLOR_BLUE}1)${COLOR_RESET} Copy configuration (top-level dotfiles), dependencies and build artifacts"
    echo "  ${COLOR_BLUE}2)${COLOR_RESET} Copy top-level configuration (dotfiles) only (you'll need to install/build yourself)"
    echo "  ${COLOR_BLUE}3)${COLOR_RESET} Don't copy anything"
  fi
  echo ""
  local mode=""
  while true; do
    printf "Select [${COLOR_BLUE}1${COLOR_RESET}/${COLOR_BLUE}2${COLOR_RESET}/${COLOR_BLUE}3${COLOR_RESET}]: "
    read -r input
    case "$input" in
      1) mode="all"; break ;;
      2) mode="config"; break ;;
      3) return 1 ;;
      *) printf "Please answer ${COLOR_BLUE}1${COLOR_RESET}, ${COLOR_BLUE}2${COLOR_RESET}, or ${COLOR_BLUE}3${COLOR_RESET}.\n" ;;
    esac
  done

  echo ""
  if $is_mac; then
    echo "Checking for cloneable gitignored files..."
  else
    echo "Checking for copyable gitignored files..."
  fi

  local clone_paths=()

  # --- Dotfiles (both modes) ---
  local dotfile_targets
  dotfile_targets="$("$scripts_dir/clone-worktree-files.sh" --list-dotfiles "$repo_root")"
  if [ -n "$dotfile_targets" ]; then
    local dotfile_options=()
    while IFS= read -r line; do dotfile_options+=("$line"); done <<< "$dotfile_targets"

    local dotfile_selected=()
    dotfile_selected=("$(clone_worktree_select_cached "$cache_dotfiles" "$repo_name" "dotfiles" "Which dotfiles to clone?" "${dotfile_options[@]}")")
    # Re-split output into array (prompt_multi_select outputs one per line)
    local dotfile_final=()
    if [ -n "${dotfile_selected[0]}" ]; then
      while IFS= read -r line; do [ -n "$line" ] && dotfile_final+=("$line"); done <<< "${dotfile_selected[0]}"
    fi
    for df in "${dotfile_final[@]+${dotfile_final[@]}}"; do clone_paths+=("$df"); done
  fi

  # --- Dirs (only in "all" mode) ---
  if [ "$mode" = "all" ]; then
    local dir_targets
    dir_targets="$("$scripts_dir/clone-worktree-files.sh" --list-dirs "$repo_root")"
    if [ -n "$dir_targets" ]; then
      local dir_options=()
      while IFS= read -r line; do dir_options+=("$line"); done <<< "$dir_targets"

      local dir_selected=()
      dir_selected=("$(clone_worktree_select_cached "$cache_dirs" "$repo_name" "dependencies/artifacts" "Which dependencies and build artifacts to clone?" "${dir_options[@]}")")
      local dir_final=()
      if [ -n "${dir_selected[0]}" ]; then
        while IFS= read -r line; do [ -n "$line" ] && dir_final+=("$line"); done <<< "${dir_selected[0]}"
      fi
      for d in "${dir_final[@]+${dir_final[@]}}"; do clone_paths+=("$d"); done
    fi
  fi

  if [ ${#clone_paths[@]} -eq 0 ]; then
    return 1
  fi

  "$scripts_dir/clone-worktree-files.sh" --clone "$repo_root" "$wt_path" "${clone_paths[@]}"
  return 0
}

# clone_worktree_select_cached <cache-file> <repo-name> <label> <prompt> <options...>
# Checks for a cached selection, offers to reuse it, or prompts with
# prompt_multi_select. Saves the new selection to the cache file.
# Prints selected items to stdout (one per line).
clone_worktree_select_cached() {
  local cache_file="$1" repo_name="$2" label="$3" prompt_msg="$4"
  shift 4
  local options=("$@")

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
      echo "" >&2
      echo "Previous ${label} selection for ${repo_name}:" >&2
      while IFS= read -r item; do echo "  - $item" >&2; done <<< "$cached"
      if prompt_yn "Use this selection?"; then
        echo "$cached"
        return
      fi
    fi
  fi

  # Prompt for new selection
  local selected
  selected="$(prompt_multi_select "$prompt_msg" "${options[@]}")"
  if [ -n "$selected" ]; then
    echo "$selected" > "$cache_file"
    echo "$selected"
  fi
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
  echo "Worktree recreated at: $(short_path "$WT_PATH")"
  return 0
}

# --- VS Code tasks.json auto-REPL support ---

WORKTREE_EXCLUDE_MARKER="worktree-script-managed"
VSCODE_TASKS_PREF_FILE="/tmp/worktree-vscode-tasks-preference"

# add_worktree_git_exclude <repo-root>
# Adds .vscode/ to .git/info/exclude with markers if not already present.
add_worktree_git_exclude() {
  local repo_root="$1"
  local exclude_file="$repo_root/.git/info/exclude"
  if grep -q "# BEGIN $WORKTREE_EXCLUDE_MARKER" "$exclude_file" 2>/dev/null; then
    return
  fi
  mkdir -p "$repo_root/.git/info"
  printf '\n# BEGIN %s\n.vscode/\n# END %s\n' "$WORKTREE_EXCLUDE_MARKER" "$WORKTREE_EXCLUDE_MARKER" >> "$exclude_file"
}

# remove_worktree_git_exclude <repo-root>
# Removes worktree-managed entries from .git/info/exclude.
remove_worktree_git_exclude() {
  local repo_root="$1"
  local exclude_file="$repo_root/.git/info/exclude"
  if [ ! -f "$exclude_file" ]; then return; fi
  if ! grep -q "# BEGIN $WORKTREE_EXCLUDE_MARKER" "$exclude_file" 2>/dev/null; then return; fi
  sed -i '' "/# BEGIN $WORKTREE_EXCLUDE_MARKER/,/# END $WORKTREE_EXCLUDE_MARKER/d" "$exclude_file"
}

# cleanup_worktree_exclude_if_last <repo-root>
# Removes git exclude entries if no non-main worktrees remain.
cleanup_worktree_exclude_if_last() {
  local repo_root="$1"
  if [ -z "$repo_root" ]; then return; fi
  local count
  count="$(git -C "$repo_root" worktree list 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$count" -le 1 ]; then
    remove_worktree_git_exclude "$repo_root"
  fi
}

# maybe_setup_vscode_tasks <wt-path> <repo-root>
# Offers to create .vscode/tasks.json for auto-starting the REPL in VS Code.
# Returns 0 if tasks were set up (caller should skip REPL), 1 otherwise.
maybe_setup_vscode_tasks() {
  local wt_path="$1" repo_root="$2"
  local tasks_file="$wt_path/.vscode/tasks.json"

  # Determine which editor was used
  local editor="${EDITOR_CMD:-}"
  if [ -z "$editor" ] && [ -f /tmp/worktree-editor-preference ]; then
    local cached
    cached="$(cat /tmp/worktree-editor-preference)"
    case "$cached" in
      "VS Code") editor="code" ;;
      "Cursor") editor="cursor" ;;
    esac
  fi
  if [ "$editor" != "code" ] && [ "$editor" != "cursor" ]; then
    return 1
  fi

  # Skip if tasks.json already exists
  if [ -f "$tasks_file" ]; then
    return 0
  fi

  # Check cached preference (only "Yes" is persisted; "No" is asked each time)
  if [ -f "$VSCODE_TASKS_PREF_FILE" ]; then
    # pref is "Yes", fall through to create
    true
  else
    # Ask user
    echo ""
    echo "Would you like VS Code to auto-start the worktree REPL in its terminal?"
    echo "(This creates a .vscode/tasks.json in the worktree, hidden from git status,"
    echo " and cleaned up automatically when the last worktree for this repo is removed)"
    if prompt_yn "Set up auto-REPL task?"; then
      echo "Yes" > "$VSCODE_TASKS_PREF_FILE"
    else
      return 1
    fi
  fi

  # Write tasks.json
  mkdir -p "$wt_path/.vscode"
  cat > "$tasks_file" <<'TASKEOF'
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Worktree REPL",
      "type": "shell",
      "command": "worktree",
      "args": ["--no-mprocs", "${workspaceFolder}"],
      "runOptions": { "runOn": "folderOpen" },
      "presentation": {
        "reveal": "always",
        "focus": true,
        "panel": "dedicated"
      },
      "isBackground": true,
      "problemMatcher": []
    }
  ]
}
TASKEOF

  # Add .vscode/ to git exclude so it doesn't pollute git status
  add_worktree_git_exclude "$repo_root"

  echo "Created .vscode/tasks.json — REPL will auto-start when this folder opens in VS Code."
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

# open_editor <worktree-path> [repo-root] - Open the worktree in an editor.
# Detects the editor, offers VS Code auto-REPL task setup if repo-root is provided,
# then opens the editor. Uses EDITOR_CMD if set (from detect_editor), otherwise uses
# cached preference, otherwise prompts the user to choose. Caches the choice.
open_editor() {
  local wt_path="$1"
  local repo_root="${2:-}"
  local cache_file="/tmp/worktree-editor-preference"

  detect_editor

  # Set up VS Code auto-REPL task before opening (so it exists when the folder opens)
  if [ -n "$repo_root" ]; then
    maybe_setup_vscode_tasks "$wt_path" "$repo_root" || true
  fi

  if [ -n "${EDITOR_CMD:-}" ]; then
    env -u CLAUDECODE $EDITOR_CMD --new-window "$wt_path"
    echo "Opened new ${EDITOR_CMD} window."
    return
  fi

  echo "No editor detected in shell context."

  # Check for cached preference
  if [ -f "$cache_file" ]; then
    local cached
    cached="$(cat "$cache_file")"
    case "$cached" in
      "VS Code")
        env -u CLAUDECODE code --new-window "$wt_path"
        echo "Opened new VS Code window (remembered preference)."
        return
        ;;
      "Cursor")
        env -u CLAUDECODE cursor --new-window "$wt_path"
        echo "Opened new Cursor window (remembered preference)."
        return
        ;;
      "None")
        ;;
    esac
  fi

  local choice
  choice="$(prompt_choice "Which editor?" "VS Code" "Cursor" "None")"
  case "$choice" in
    "VS Code") echo "$choice" > "$cache_file"; env -u CLAUDECODE code --new-window "$wt_path" ;;
    "Cursor") echo "$choice" > "$cache_file"; env -u CLAUDECODE cursor --new-window "$wt_path" ;;
    "None") echo "Skipping editor." ;;
  esac
}

# worktree_repl <repo-root> <worktree-path>
# Interactive loop offering shell, open, cleanup, and exit commands.
worktree_repl() {
  local repo_root="$1" wt_path="$2" scripts_dir="${3:-}"
  local wt_name branch tracking pr_num pr_url
  wt_name="$(basename "$wt_path")"
  branch="$(git -C "$wt_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"
  tracking="$(git -C "$wt_path" rev-parse --abbrev-ref "@{upstream}" 2>/dev/null || true)"

  if [[ "$wt_name" == *--pr-* ]]; then
    pr_num="$(echo "$wt_name" | sed 's/.*--pr-\([0-9]*\)-.*/\1/')"
    local remote_url
    remote_url="$(git -C "$wt_path" remote get-url upstream 2>/dev/null || git -C "$wt_path" remote get-url origin 2>/dev/null || true)"
    if [ -n "$remote_url" ]; then
      pr_url="$(echo "$remote_url" | sed 's/\.git$//' | sed 's|git@github.com:|https://github.com/|')/pull/${pr_num}"
    fi
  fi

  # If no PR was found from the worktree name, check if the branch has an open PR
  if [ -z "$pr_url" ] && [ "$branch" != "unknown" ]; then
    local detected_pr_url
    detected_pr_url="$(gh pr view "$branch" --json url --jq '.url' 2>/dev/null || true)"
    if [ -n "$detected_pr_url" ]; then
      pr_url="$detected_pr_url"
      pr_num="$(echo "$detected_pr_url" | grep -o '[0-9]*$')"
    fi
  fi

  # Fetch PR details (author, created date, last updated) if we have a PR
  local pr_author pr_created pr_updated
  if [ -n "$pr_url" ]; then
    local pr_details
    pr_details="$(gh pr view "$pr_url" --json author,createdAt,updatedAt 2>/dev/null || true)"
    if [ -n "$pr_details" ]; then
      pr_author="$(echo "$pr_details" | python3 -c "import sys,json; print(json.load(sys.stdin).get('author',{}).get('login',''))" 2>/dev/null || true)"
      pr_created="$(echo "$pr_details" | python3 -c "import sys,json; print(json.load(sys.stdin).get('createdAt',''))" 2>/dev/null || true)"
      pr_updated="$(echo "$pr_details" | python3 -c "import sys,json; print(json.load(sys.stdin).get('updatedAt',''))" 2>/dev/null || true)"
    fi
  fi

  # --- Open editor (detects editor and sets up auto-REPL task internally) ---
  echo ""
  open_editor "$wt_path" "$repo_root"

  local blue cyan green red reset
  blue="$(tput setaf 12 2>/dev/null || true)"
  cyan="$(tput setaf 6 2>/dev/null || true)"
  green="$(tput setaf 2 2>/dev/null || true)"
  red="$(tput setaf 1 2>/dev/null || true)"
  reset="$(tput sgr0 2>/dev/null || true)"

  _worktree_info() {
    local show_path="${1:-true}"
    if [ "$show_path" = "true" ]; then
      echo "${cyan}Path:${reset} $(short_path "$wt_path")"
    fi
    echo "${cyan}Branch:${reset} ${branch}"
    if [ -n "${pr_num:-}" ]; then
      local pr_info="#${pr_num}"
      if [ -n "${pr_author:-}" ]; then
        pr_info="${pr_info} by ${pr_author}"
      fi
      echo "${cyan}PR:${reset} ${pr_info}${pr_url:+ — $pr_url}"
      if [ -n "${pr_created:-}" ]; then
        echo "${cyan}Created:${reset} $(relative_time "$pr_created")"
      fi
      if [ -n "${pr_updated:-}" ]; then
        echo "${cyan}Updated:${reset} $(relative_time "$pr_updated")"
      fi
    fi
    if [ -n "$tracking" ]; then
      local info_ahead info_behind info_parts=""
      info_ahead="$(git -C "$wt_path" rev-list --count "${tracking}..HEAD" 2>/dev/null || echo 0)"
      info_behind="$(git -C "$wt_path" rev-list --count "HEAD..${tracking}" 2>/dev/null || echo 0)"
      if [ "$info_ahead" -eq 0 ] && [ "$info_behind" -eq 0 ]; then
        echo "${cyan}Tracking:${reset} up to date with ${tracking}"
      else
        if [ "$info_ahead" -gt 0 ]; then
          local w="commits"; [ "$info_ahead" -eq 1 ] && w="commit"
          info_parts="${info_ahead} ${w} ahead"
        fi
        if [ "$info_behind" -gt 0 ]; then
          local w="commits"; [ "$info_behind" -eq 1 ] && w="commit"
          [ -n "$info_parts" ] && info_parts="${info_parts}, "
          info_parts="${info_parts}${info_behind} ${w} behind"
        fi
        echo "${cyan}Tracking:${reset} ${info_parts} ${tracking}"
      fi
    fi
    if [ -n "${worktree_ports:-}" ]; then
      echo "${cyan}Environment:${reset}"
      echo "  WORKTREE_PORTS=${worktree_ports} (reserved for dev servers in this worktree's child shell)"
    fi
    if [ -z "$(git -C "$wt_path" status --short)" ]; then
      echo "${cyan}Git status:${reset} working tree clean"
    else
      echo "${cyan}Git status:${reset}"
      git -C "$wt_path" status --short
    fi
  }

  _worktree_commands() {
    local pr_cmd="" clone_cmd=""
    if [ -n "${pr_url:-}" ]; then
      pr_cmd="[p]r, "
    fi
    if [ -n "$scripts_dir" ]; then
      clone_cmd="[c]lone files, "
    fi
    echo "${blue}Commands: [h]elp, [i]nfo, [l]og, [o]pen, ${pr_cmd}${clone_cmd}[s]hell, [r]emove, [e]xit${reset}"
  }

  _worktree_help() {
    echo ""
    echo "  ${blue}help${reset}     (h)  Show this help"
    echo "  ${blue}info${reset}     (i)  Show PR URL (if applicable), worktree path, and git status"
    echo "  ${blue}log${reset}      (l)  Show git log"
    echo "  ${blue}open${reset}     (o)  Open worktree in your editor (focuses existing window if already open)"
    echo "  ${blue}pr${reset}       (p)  Open the pull request page on GitHub (if applicable)"
    if [ -n "$scripts_dir" ]; then
      echo "  ${blue}clone${reset}    (c)  Clone gitignored files (dotfiles, dependencies) from the main repo"
    fi
    echo "  ${blue}shell${reset}    (s)  Start a nested shell in the worktree directory; exit to return to REPL"
    echo "  ${blue}remove${reset}   (r)  Remove the worktree and its branch"
    echo "  ${blue}exit${reset}     (e)  Exit the REPL"
  }

  # Assign port range for this worktree
  local worktree_ports
  worktree_ports="$(assign_port_range "$wt_name")"

  # Set iTerm2 tab title and WORKTREE_TITLE
  local worktree_title iterm_label=""
  if [ -n "${pr_num:-}" ]; then
    worktree_title="wt PR #${pr_num}"
  else
    worktree_title="wt ${branch}"
  fi
  if [ "$TERM_PROGRAM" = "iTerm.app" ]; then
    iterm_label="$worktree_title"
    printf '\033]1;%s\007' "$iterm_label"
  fi

  _worktree_info false
  if [ -n "$scripts_dir" ]; then
    echo ""
    echo "Tip: use [c]lone files to reuse installed dependencies and configuration from the main repo"
  fi
  while true; do
    echo ""
    _worktree_commands
    if [ -n "$tracking" ]; then
      printf "\nworktree [${green}%s${reset}...${red}%s${reset}]> " "$branch" "$tracking"
    else
      printf "\nworktree [${green}%s${reset}]> " "$branch"
    fi
    read -r cmd
    case "$cmd" in
      info|i)
        echo ""
        _worktree_info
        ;;
      log|l)
        git -C "$wt_path" log --oneline --graph --decorate || true
        ;;
      open|o)
        open_editor "$wt_path" "$repo_root"
        ;;
      pr|p)
        if [ -n "${pr_url:-}" ]; then
          echo "Opening ${pr_url}"
          open "$pr_url"
        else
          echo "No open pull request found for this branch."
        fi
        ;;
      shell|s)
        echo "Starting shell in $(short_path "$wt_path")"
        echo "Exit the shell to return to this REPL."
        (cd "$wt_path" && WORKTREE_PORTS="$worktree_ports" WORKTREE_TITLE="$worktree_title" "$SHELL")
        echo ""
        echo "Back in worktree REPL."
        if [ -n "$iterm_label" ]; then
          printf '\033]1;%s\007' "$iterm_label"
        fi
        _worktree_info
        ;;
      clone|c)
        if [ -n "$scripts_dir" ]; then
          clone_worktree_files "$scripts_dir" "$repo_root" "$wt_path" || true
        else
          echo "Clone files not available (missing scripts directory)."
        fi
        ;;
      remove|r)
        echo "This will remove the worktree at:"
        echo "  $(short_path "$wt_path")"
        if prompt_yn "Proceed?"; then
          release_port_range "$wt_name"
          remove_worktree "$wt_path"
          echo "Worktree removed."
          git worktree prune 2>/dev/null || true
          cleanup_worktree_exclude_if_last "$repo_root"
          if [ -n "${WORKTREE_MPROCS_PANE:-}" ]; then
            echo ""
            echo "To close this pane: Ctrl+A → d → y"
          fi
          exit 0
        fi
        ;;
      exit|quit|q|e)
        if [ -n "${WORKTREE_MPROCS_PANE:-}" ]; then
          echo ""
          echo "To close this pane: Ctrl+A → d → y"
        fi
        exit 0
        ;;
      help|h)
        _worktree_help
        ;;
      "")
        ;;
      *)
        echo "Unknown command: $cmd. Type 'help' for usage."
        ;;
    esac
  done
}

parse_json() {
  python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('$1',''))" 2>/dev/null
}

# worktree_post_setup <scripts-dir> <repo-root> <worktree-path>
# Handles starting the REPL after initial worktree creation.
worktree_post_setup() {
  local scripts_dir="$1" repo_root="$2" wt_path="$3"
  worktree_repl "$repo_root" "$wt_path" "$scripts_dir"
}

# resolve_worktree <arg>
# Resolves a worktree path from a PR number, PR URL, branch name, or direct path.
# Sets WT_PATH to the resolved absolute path. Returns 1 if not found.
resolve_worktree() {
  local arg="$1"
  WT_PATH=""

  # Case 1: Direct path to a worktree
  if [ -d "$arg" ] && [ -e "$arg/.git" ]; then
    WT_PATH="$(cd "$arg" && pwd)"
    return 0
  elif [ -d "$WORKTREES_BASE/$arg" ] && [ -e "$WORKTREES_BASE/$arg/.git" ]; then
    WT_PATH="$WORKTREES_BASE/$arg"
    return 0
  fi

  # Case 2: PR number or URL
  local pr_number=""
  if [[ "$arg" == *github.com* ]]; then
    pr_number="$(echo "$arg" | grep -o '[0-9]*$' || true)"
  elif [[ "$arg" =~ ^[0-9]+$ ]]; then
    pr_number="$arg"
  fi

  if [ -n "$pr_number" ]; then
    if [ -d "$WORKTREES_BASE" ]; then
      while IFS= read -r candidate; do
        if [ -d "$candidate" ]; then
          WT_PATH="$candidate"
          return 0
        fi
      done < <(find "$WORKTREES_BASE" -maxdepth 1 -type d -name "*--pr-${pr_number}-*" 2>/dev/null)
    fi
    return 1
  fi

  # Case 3: Branch name
  local dir_branch
  dir_branch="$(echo "$arg" | tr '/' '-')"
  if [ -d "$WORKTREES_BASE" ]; then
    while IFS= read -r candidate; do
      if [ -d "$candidate" ]; then
        WT_PATH="$candidate"
        return 0
      fi
    done < <(find "$WORKTREES_BASE" -maxdepth 1 -type d -name "*--${dir_branch}" 2>/dev/null)
  fi

  # Also check git worktree list for the branch
  local existing_wt
  existing_wt="$(git worktree list --porcelain 2>/dev/null | awk -v branch="$arg" '
    /^worktree / { wt = $0; sub(/^worktree /, "", wt) }
    /^branch refs\/heads\// {
      b = $0; sub(/^branch refs\/heads\//, "", b)
      if (b == branch) { print wt; exit }
    }
  ')"
  if [ -n "$existing_wt" ]; then
    WT_PATH="$existing_wt"
    return 0
  fi

  return 1
}

# repo_matches_target <repo-path> <owner/repo>
# Returns 0 if the repo at the given path has a remote matching the target.
repo_matches_target() {
  git -C "$1" remote -v 2>/dev/null | grep -q "$2"
}

# warn_pr_local_changes <worktree-path>
# Warns about uncommitted changes before destructive operations.
# Returns 1 if the user aborts.
warn_pr_local_changes() {
  local wt_path="$1"
  local changes
  changes="$(git -C "$wt_path" status --porcelain 2>/dev/null)"
  if [ -n "$changes" ]; then
    echo ""
    echo "WARNING: Worktree has uncommitted changes:"
    echo "$changes"
    if ! prompt_yn "Continue? These changes will be lost."; then
      return 1
    fi
  fi
  return 0
}

# setup_pr_tracking <worktree-path> <local-branch> <pr-head-owner> <pr-head-ref>
# Finds the git remote matching the PR owner and sets the local branch to track it.
setup_pr_tracking() {
  local wt_path="$1" local_branch="$2" head_owner="$3" head_ref="$4"
  if [ -z "$head_owner" ] || [ -z "$head_ref" ]; then
    return 0
  fi
  local remote_name=""
  while IFS= read -r line; do
    local name url
    name="$(echo "$line" | awk '{print $1}')"
    url="$(echo "$line" | awk '{print $2}')"
    if echo "$url" | grep -qi "github\.com[:/]${head_owner}/"; then
      remote_name="$name"
      break
    fi
  done < <(git remote -v | grep '(fetch)')

  if [ -z "$remote_name" ]; then
    echo "Note: No git remote found for '${head_owner}'. Branch tracking not set."
    return 0
  fi

  git fetch "$remote_name" "$head_ref" 2>/dev/null || true
  git -C "$wt_path" branch --set-upstream-to="${remote_name}/${head_ref}" "$local_branch" 2>/dev/null || true
  # The local branch name (review/pr-*) differs from the remote branch name,
  # so set push.default=upstream to allow `git push` without the name mismatch error.
  git -C "$wt_path" config push.default upstream
}

# recreate_pr_worktree <scripts-dir> <worktree-abs> <pr-number> <slug> <base-repo> <wt-path>
# Removes the PR worktree and branch, then recreates both.
# Sets WT_PATH to the new worktree path. Returns 1 if user aborts.
recreate_pr_worktree() {
  local scripts_dir="$1" worktree_abs="$2" pr_number="$3" slug="$4" base_repo="$5" wt_path="$6"
  local pr_branch="review/pr-${pr_number}-${slug}"
  warn_pr_local_changes "$wt_path" || return 1
  remove_worktree "$wt_path"
  git branch -D "$pr_branch" 2>/dev/null || true
  if ! RESULT="$("$scripts_dir/worktree-ensure.sh" pr "$worktree_abs" "$pr_number" "$slug" "$base_repo" 2>&1)"; then
    local msg
    msg="$(echo "$RESULT" | parse_json message)"
    echo "ERROR: Failed to recreate worktree." >&2
    [ -n "$msg" ] && echo "  $msg" >&2
    return 1
  fi
  WT_PATH="$(echo "$RESULT" | parse_json path)"
  echo "Worktree recreated at: $(short_path "$WT_PATH")"
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
