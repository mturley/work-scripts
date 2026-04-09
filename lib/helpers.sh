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
# Uses EDITOR_CMD if set (from detect_editor), otherwise uses cached preference,
# otherwise prompts the user to choose. Caches the choice for future runs.
open_editor() {
  local wt_path="$1"
  local cache_file="/tmp/worktree-editor-preference"

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
    if [ -n "${pr_num:-}" ]; then
      echo "${cyan}PR:${reset} #${pr_num}${pr_url:+ — $pr_url}"
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
      echo "${cyan}Ports:${reset} ${worktree_ports} (dev servers can use ports in this range)"
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
    echo "${blue}Commands: [i]nfo, [l]og, [o]pen, ${pr_cmd}${clone_cmd}[s]hell, [r]emove, [e]xit, [h]elp${reset}"
  }

  _worktree_help() {
    echo ""
    echo "  ${blue}info${reset}     (i)  Show PR URL (if applicable), worktree path, and git status"
    echo "  ${blue}log${reset}      (l)  Show git log"
    echo "  ${blue}open${reset}     (o)  Open worktree in your editor (focuses existing window if already open)"
    if [ -n "${pr_url:-}" ]; then
      echo "  ${blue}pr${reset}       (p)  Open the pull request page on GitHub"
    fi
    if [ -n "$scripts_dir" ]; then
      echo "  ${blue}clone${reset}    (c)  Clone gitignored files (dotfiles, dependencies) from the main repo"
    fi
    echo "  ${blue}shell${reset}    (s)  Start a nested shell in the worktree directory; exit to return to REPL"
    echo "  ${blue}remove${reset}   (r)  Remove the worktree and its branch"
    echo "  ${blue}exit${reset}     (e)  Exit the REPL"
    echo "  ${blue}help${reset}     (h)  Show this help"
  }

  # Assign port range for this worktree
  local worktree_ports
  worktree_ports="$(assign_port_range "$wt_name")"

  # Set iTerm2 tab title and WORKTREE_TITLE
  local worktree_title iterm_label=""
  if [ -n "${pr_num:-}" ]; then
    worktree_title="worktree PR #${pr_num}"
  else
    worktree_title="worktree ${branch}"
  fi
  if [ "$TERM_PROGRAM" = "iTerm.app" ]; then
    iterm_label="$worktree_title"
    printf '\033]1;%s\007' "$iterm_label"
  fi

  _worktree_info false
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
        open_editor "$wt_path"
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
          git worktree prune 2>/dev/null
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
# Handles cloning gitignored files, opening editor, and starting the REPL.
worktree_post_setup() {
  local scripts_dir="$1" repo_root="$2" wt_path="$3"

  # --- Clone Gitignored Files ---
  clone_worktree_files "$scripts_dir" "$repo_root" "$wt_path" || true

  # --- Detect Editor and Open ---
  echo ""
  detect_editor
  open_editor "$wt_path"

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
