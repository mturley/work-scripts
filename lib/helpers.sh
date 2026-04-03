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

# force_rm <path> - Remove a directory, prompting to fix permissions if needed
force_rm() {
  local target="$1"
  echo "Removing $(basename "$target")..."
  rm -rf "$target" 2>/dev/null &
  spin_wait $! "deleting files..."
  local exit_code=$?
  if [ $exit_code -eq 0 ] && [ ! -d "$target" ]; then
    return 0
  fi
  # Check if the failure was permission-related
  local err
  err="$(rm -rf "$target" 2>&1)" || true
  if echo "$err" | grep -q "Permission denied"; then
    echo "" >&2
    echo "Permission denied removing: $target" >&2
    echo "This can happen with downloaded binaries (e.g. k8s test fixtures)." >&2
    if prompt_yn "Run chmod -R u+rwx and retry?"; then
      echo "Fixing permissions..."
      chmod -R u+rwx "$target"
      echo "Retrying removal..."
      force_rm "$target"
      return $?
    else
      echo "Skipping removal." >&2
      return 1
    fi
  fi
  # Non-permission error
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

# link_worktree_files <scripts-dir> <repo-root> <worktree-path>
# Finds linkable files, prompts user to select (with caching), and links.
# Returns 0 if files were linked, 1 otherwise.
link_worktree_files() {
  local scripts_dir="$1" repo_root="$2" wt_path="$3"
  local repo_name
  repo_name="$(basename "$repo_root")"
  local cache_file="/tmp/worktree-link-selection-${repo_name}"

  echo "Checking for linkable files (node_modules, build outputs, config)..."
  local dir_targets dotfile_targets
  dir_targets="$("$scripts_dir/link-worktree-files.sh" --list-dirs "$repo_root")"
  dotfile_targets="$("$scripts_dir/link-worktree-files.sh" --list-dotfiles "$repo_root")"

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
    echo "NOTE: Linked files are shared with the main clone. Changes like" >&2
    echo "installing or removing dependencies will affect both. Select \"none\"" >&2
    echo "and install separately if you need different versions." >&2
    while IFS= read -r line; do [ -n "$line" ] && selected+=("$line"); done < <(prompt_multi_select "Which files to link into the new worktree?" "${options[@]}")
    # Save selection
    if [ ${#selected[@]} -gt 0 ]; then
      printf '%s\n' "${selected[@]}" > "$cache_file"
    fi
  fi

  if [ ${#selected[@]} -eq 0 ]; then
    return 1
  fi

  # Expand "Top-level dotfiles" into individual paths
  local link_paths=()
  for item in "${selected[@]}"; do
    if [ "$item" = "Top-level dotfiles" ]; then
      while IFS= read -r df; do link_paths+=("$df"); done <<< "$dotfile_targets"
    else
      link_paths+=("$item")
    fi
  done

  if [ ${#link_paths[@]} -gt 0 ]; then
    "$scripts_dir/link-worktree-files.sh" --link "$repo_root" "$wt_path" "${link_paths[@]}"
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

  echo "No editor detected."

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
        echo "Skipping editor (remembered preference)."
        return
        ;;
    esac
  fi

  local choice
  choice="$(prompt_choice "Which editor?" "VS Code" "Cursor" "None")"
  echo "$choice" > "$cache_file"
  case "$choice" in
    "VS Code") env -u CLAUDECODE code --new-window "$wt_path" ;;
    "Cursor") env -u CLAUDECODE cursor --new-window "$wt_path" ;;
    "None") echo "Skipping editor." ;;
  esac
}

# worktree_repl <repo-root> <worktree-path>
# Interactive loop offering cleanup, open, status, and exit commands.
worktree_repl() {
  local repo_root="$1" wt_path="$2"
  echo ""
  echo "Commands: [o]pen, [s]tatus, [c]leanup, [e]xit"
  while true; do
    printf "\nworktree> "
    read -r cmd
    case "$cmd" in
      open|o)
        open_editor "$wt_path"
        ;;
      status|s)
        git -C "$wt_path" status
        ;;
      cleanup|c)
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
      exit|quit|q|e)
        exit 0
        ;;
      "")
        ;;
      *)
        echo "Unknown command: $cmd"
        echo "Commands: [o]pen, [s]tatus, [c]leanup, [e]xit"
        ;;
    esac
  done
}

parse_json() {
  python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('$1',''))" 2>/dev/null
}

# worktree_post_setup <scripts-dir> <repo-root> <worktree-path> <label> <detail-lines...>
# Handles copy-files, editor open, summary banner, and REPL.
# label: e.g. "PR Worktree Ready!" or "Branch Worktree Ready!"
# detail-lines: lines to print in the summary (e.g. "PR:  #123 - title")
worktree_post_setup() {
  local scripts_dir="$1" repo_root="$2" wt_path="$3" label="$4"
  shift 4

  # --- Link Gitignored Files ---
  link_worktree_files "$scripts_dir" "$repo_root" "$wt_path" || true

  # --- Detect Editor and Open ---
  echo ""
  detect_editor
  open_editor "$wt_path"

  # --- Post-Setup Summary ---
  echo ""
  echo "============================================"
  echo "$label"
  echo "============================================"
  echo ""
  for line in "$@"; do
    echo "$line"
  done

  worktree_repl "$repo_root" "$wt_path"
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
  echo "Worktree recreated at: ${WT_PATH}"
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
