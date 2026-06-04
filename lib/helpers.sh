#!/usr/bin/env bash
# helpers.sh - Shared helper functions for worktree scripts

# Base directory for all worktrees. Override with WORKTREES_BASE env var.
WORKTREES_BASE="${WORKTREES_BASE:-$HOME/git/.worktrees}"

# Worktree discovery settings (for finding worktrees created by any tool)
WORKTREE_SEARCH_ROOTS="${WORKTREE_SEARCH_ROOTS:-$HOME/git}"
WORKTREE_SEARCH_DEPTH="${WORKTREE_SEARCH_DEPTH:-5}"
WORKTREE_SEARCH_PRUNE="${WORKTREE_SEARCH_PRUNE:-node_modules:.Trash:.cache:.venv:venv}"

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

# --- Persistent session (screen) helpers ---

# require_screen_5
# Checks that GNU Screen >= 5.0 is installed and on PATH.
# Prints an error and returns 1 if the version is too old or screen is missing.
require_screen_5() {
  if ! command -v screen &>/dev/null; then
    echo "ERROR: --persistent requires GNU Screen >= 5.0." >&2
    echo "  Install screen: brew install screen" >&2
    return 1
  fi
  local version_output
  version_output="$(screen --version 2>&1 || true)"
  local major=""
  major="$(echo "$version_output" | sed -n 's/.*Screen version \([0-9]*\)\..*/\1/p')"
  if [ -z "$major" ]; then
    major="$(echo "$version_output" | sed -n 's/.*version \([0-9]*\)\..*/\1/p')"
  fi
  if [ -z "$major" ] || [ "$major" -lt 5 ] 2>/dev/null; then
    local found_ver
    found_ver="$(echo "$version_output" | head -1)"
    echo "ERROR: GNU Screen >= 5.0 required." >&2
    echo "  Found: $found_ver" >&2
    echo "  Install with: brew install screen" >&2
    echo "  Ensure Homebrew's screen is on PATH before /usr/bin/screen." >&2
    return 1
  fi
}

# screen_session_name <arg1> [arg2 ...]
# Derives a stable, human-readable screen session name from worktree arguments.
# Single arg: wt-<sanitized-label>
# Multiple args: wt-multi-<8-char-hash>
screen_session_name() {
  if [ $# -eq 1 ]; then
    local sanitized
    sanitized="$(echo "$1" | sed 's/[^a-zA-Z0-9._-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')"
    # screen session names have practical length limits
    sanitized="${sanitized:0:48}"
    echo "wt-${sanitized}"
  else
    local combined=""
    local arg
    for arg in "$@"; do
      combined="${combined}${arg}|"
    done
    local hash
    if command -v md5 &>/dev/null; then
      hash="$(echo -n "$combined" | md5 -q)"
    elif command -v md5sum &>/dev/null; then
      hash="$(echo -n "$combined" | md5sum | awk '{print $1}')"
    else
      hash="$(echo -n "$combined" | cksum | awk '{print $1}')"
    fi
    echo "wt-multi-${hash:0:8}"
  fi
}

# screen_mprocs_port <session-name>
# Derives a deterministic mprocs server port from a screen session name.
# Port range: 19000-19999.
screen_mprocs_port() {
  local name="$1"
  local hash
  if command -v cksum &>/dev/null; then
    hash="$(echo -n "$name" | cksum | awk '{print $1}')"
  else
    hash="$(echo -n "$name" | sum | awk '{print $1}')"
  fi
  echo $((19000 + (hash % 1000)))
}

# screen_mprocs_socket <session-name>
# Reads the mprocs socket address for a persistent session from its socket file.
# Returns empty string if the file doesn't exist.
screen_mprocs_socket() {
  local session_name="$1"
  local sock_file="/tmp/worktree-screen-${session_name}.sock"
  if [ -f "$sock_file" ]; then
    cat "$sock_file"
  fi
}

# screen_has_session <session-name>
# Returns 0 if a screen session with the given name exists.
screen_has_session() {
  screen -ls 2>/dev/null | grep -q "[0-9]*\.${1}[[:space:]]"
}

# screen_session_is_attached <session-name>
# Returns 0 if the session exists and is currently attached.
screen_session_is_attached() {
  screen -ls 2>/dev/null | grep "[0-9]*\.${1}[[:space:]]" | grep -qi "attached"
}

# screen_kill_session <session-name>
# Kills a screen session by name.
screen_kill_session() {
  screen -S "$1" -X quit 2>/dev/null
}

# screen_attach <session-name>
# Attaches to a screen session. If the session is already attached elsewhere,
# prompts the user to detach+reattach, multi-attach, or abort.
# Uses exec to replace the current process.
screen_attach() {
  local session_name="$1"
  if screen_session_is_attached "$session_name"; then
    echo "Session '$session_name' is attached in another terminal."
    local choice
    choice="$(prompt_choice "How to proceed?" \
      "Detach other and attach here" \
      "Multi-attach (shared session)" \
      "Abort")"
    case "$choice" in
      "Detach other and attach here")
        exec screen -d -r "$session_name"
        ;;
      "Multi-attach (shared session)")
        exec screen -x "$session_name"
        ;;
      "Abort")
        return 1
        ;;
    esac
  else
    exec screen -r "$session_name"
  fi
}

# launch_mprocs_persistent <session_name> <mprocs_cfg> <mprocs_sock> <mprocs_count>
# Launches mprocs inside a screen session, or reattaches to an existing one.
launch_mprocs_persistent() {
  local session_name="$1" mprocs_cfg="$2" mprocs_sock="$3" mprocs_count="$4"

  require_screen_5 || return 1

  # Warn about nested screen
  if [ -n "${STY:-}" ]; then
    echo "Already inside a screen session."
    echo "Attaching will create a nested screen session."
    if ! prompt_yn "Attach anyway?"; then
      return 2
    fi
  fi

  local sock_file="/tmp/worktree-screen-${session_name}.sock"

  if screen_has_session "$session_name"; then
    echo "Reattaching to persistent session: $session_name"
    screen_attach "$session_name"
    return $?
  fi

  # New session — disable cleanup trap (mprocs will run beyond this script)
  trap "" EXIT

  echo "$mprocs_sock" > "$sock_file"

  # Write a minimal screenrc for this session
  local screenrc="/tmp/worktree-screenrc-${session_name}"
  cat > "$screenrc" <<SCREENRC_EOF
startup_message off
mousetrack on
hardstatus off
caption splitonly
truecolor on
term xterm-256color
SCREENRC_EOF

  # Launch mprocs inside screen via a wrapper script that traps EXIT to ensure
  # cleanup happens even if mprocs is force-quit (signal death skips ;-chained commands)
  local wrapper="/tmp/worktree-launch-${session_name}.sh"
  cat > "$wrapper" <<WRAPPER_EOF
#!/usr/bin/env bash
cleanup() { rm -f '$mprocs_cfg' '$mprocs_count' '$sock_file' '$wrapper' '$screenrc'; screen -S '$session_name' -X quit 2>/dev/null; }
trap cleanup EXIT
mprocs --config '$mprocs_cfg' --server '$mprocs_sock'
WRAPPER_EOF
  chmod +x "$wrapper"
  screen -c "$screenrc" -dmS "$session_name" "$wrapper"
  exec screen -r "$session_name"
}

# list_persistent_sessions
# Lists all active worktree screen sessions with their attached/detached status.
list_persistent_sessions() {
  if ! command -v screen &>/dev/null; then
    echo "screen is not installed." >&2
    return 1
  fi
  local found=false
  while IFS= read -r line; do
    # screen -ls lines look like: "	12345.wt-all	(Detached)" or "(Attached)"
    local session_name
    session_name="$(echo "$line" | sed -n 's/.*[0-9]*\.\(wt-[^[:space:]]*\).*/\1/p')"
    if [ -n "$session_name" ]; then
      local status_label=""
      if echo "$line" | grep -qi "attached"; then
        status_label=" (attached)"
      fi
      echo "  ${session_name}${status_label}"
      found=true
    fi
  done < <(screen -ls 2>/dev/null || true)
  if ! $found; then
    echo "  (none)"
  fi
}

# --- cmux helpers ---

# cmux_is_available
# Returns 0 if we're running inside cmux.
cmux_is_available() {
  [ -n "${CMUX_SOCKET_PATH:-}" ]
}

# cmux_find_workspace_by_cwd <path>
# Checks if a cmux workspace exists whose current_directory matches <path>.
# Prints the workspace ref (e.g. "workspace:3") if found, empty string if not.
cmux_find_workspace_by_cwd() {
  local target_path="$1"
  cmux rpc workspace.list '{}' 2>/dev/null \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
target = sys.argv[1]
for ws in data.get('workspaces', []):
    if ws.get('current_directory', '') == target:
        print(ws['ref'])
        sys.exit(0)
" "$target_path" 2>/dev/null
}

# cmux_open_worktree <label> <worktree-path> <--focus|--no-focus> [<pr-url>] [<jira-url>]
# Finds an existing cmux workspace by working directory or creates a new one.
# If found, selects it. If not, creates a workspace with a split layout:
#   - Top-left (1/3): worktree REPL
#   - Bottom-left (2/3): cmux claude-teams
#   - Right (optional, 50/50): browser tabs for PR and/or Jira URLs
cmux_open_worktree() {
  local label="$1" wt_path="$2"
  local focus="true"
  if [ "${3:-}" = "--no-focus" ]; then
    focus="false"
  fi
  local pr_url="${4:-}" jira_url="${5:-}"
  local existing_ref
  if [ -d "$wt_path" ]; then
    existing_ref="$(cmux_find_workspace_by_cwd "$wt_path")"
  fi
  if [ -n "${existing_ref:-}" ]; then
    if [ "$focus" = "true" ]; then
      cmux select-workspace --workspace "$existing_ref" >/dev/null 2>&1
      echo "Switched to workspace: $label"
    fi
  else
    worktree_check_shell_rc
    local self_cmd
    self_cmd="$(command -v worktree 2>/dev/null || echo worktree)"

    # Build left side: vertical split (1/3 top, 2/3 bottom)
    local left_layout
    left_layout="{\"direction\":\"vertical\",\"split\":0.33,\"children\":["
    # Top pane: worktree REPL tab
    left_layout="${left_layout}{\"pane\":{\"surfaces\":["
    left_layout="${left_layout}{\"type\":\"terminal\",\"command\":\"${self_cmd}\"}"
    left_layout="${left_layout}]}},"
    # Bottom pane: claude
    left_layout="${left_layout}{\"pane\":{\"surfaces\":["
    left_layout="${left_layout}{\"type\":\"terminal\",\"command\":\"clear && claude\"}"
    left_layout="${left_layout}]}}"
    left_layout="${left_layout}]}"

    local layout_json
    # If we have browser URLs, wrap in horizontal split
    if [ -n "$pr_url" ] || [ -n "$jira_url" ]; then
      local browser_surfaces=""
      if [ -n "$jira_url" ]; then
        browser_surfaces="{\"type\":\"browser\",\"url\":\"${jira_url}\"}"
      fi
      if [ -n "$pr_url" ]; then
        if [ -n "$browser_surfaces" ]; then
          browser_surfaces="${browser_surfaces},"
        fi
        browser_surfaces="${browser_surfaces}{\"type\":\"browser\",\"url\":\"${pr_url}\"}"
      fi
      layout_json="{\"direction\":\"horizontal\",\"split\":0.5,\"children\":["
      layout_json="${layout_json}${left_layout},"
      layout_json="${layout_json}{\"pane\":{\"surfaces\":[${browser_surfaces}]}}"
      layout_json="${layout_json}]}"
    else
      layout_json="$left_layout"
    fi

    local ws_output
    ws_output="$(cmux new-workspace --name "$label" --cwd "$wt_path" --focus "$focus" --layout "$layout_json" 2>&1)"
    local ws_ref
    ws_ref="$(echo "$ws_output" | awk '{print $2}')"

    # Rename the worktree REPL tab (second surface in the first pane)
    if [ -n "$ws_ref" ]; then
      local first_pane
      first_pane="$(cmux list-panes --workspace "$ws_ref" 2>/dev/null | awk 'NR==1 {for(i=1;i<=NF;i++) if($i ~ /^pane:/) {print $i; exit}}')"
      if [ -n "$first_pane" ]; then
        local worktree_surface
        worktree_surface="$(cmux list-pane-surfaces --workspace "$ws_ref" --pane "$first_pane" 2>/dev/null | awk 'NR==1 {for(i=1;i<=NF;i++) if($i ~ /^surface:/) {print $i; exit}}')"
        if [ -n "$worktree_surface" ]; then
          cmux rename-tab --workspace "$ws_ref" --surface "$worktree_surface" "worktree" >/dev/null 2>&1
        fi
      fi
    fi

    echo "Created workspace: $label"
  fi
}

# --- Worktree environment file ---

WORKTREE_ENV_FILENAME=".worktree-env"
# worktree_write_env_file <worktree-path> <worktree-ports> <worktree-title>
# Writes a .worktree-env file in the worktree directory with env vars
# and a one-time info display that any shell can source automatically.
worktree_write_env_file() {
  local wt_path="$1" ports="$2" title="$3"
  local wt_name wt_repo wt_kubeconfig source_kubeconfig
  wt_name="$(basename "$wt_path")"
  wt_repo="$(basename "$(dirname "$wt_path")")"
  wt_kubeconfig="$HOME/.kube/config-${wt_repo}-${wt_name}"

  # Seed the worktree's kubeconfig from the current one if it doesn't exist yet
  if [ ! -f "$wt_kubeconfig" ]; then
    source_kubeconfig="${KUBECONFIG:-$HOME/.kube/config}"
    if [ -f "$source_kubeconfig" ]; then
      cp "$source_kubeconfig" "$wt_kubeconfig"
    fi
  fi

  cat > "$wt_path/$WORKTREE_ENV_FILENAME" <<ENVEOF
# Auto-generated by worktree script — do not edit
export WORKTREE_PORTS="$ports"
export WORKTREE_TITLE="$title"
export WORKTREE_PATH="$wt_path"
export KUBECONFIG="$wt_kubeconfig"
case "\$-" in *i*)
  if [ -z "\${_WORKTREE_ENV_SHOWN:-}" ]; then
    _WORKTREE_ENV_SHOWN=1
    if command -v worktree >/dev/null 2>&1; then
      worktree --info-simple
    fi
  fi
;; esac
ENVEOF

  # Ensure .worktree-env is in the repo's git exclude
  local repo_root
  repo_root="$(git -C "$wt_path" worktree list --porcelain 2>/dev/null | head -1 | sed 's/^worktree //')"
  if [ -n "$repo_root" ]; then
    add_worktree_git_exclude "$repo_root"
  fi
}

# worktree_check_shell_rc
# Checks if the user's shell RC file has the auto-source snippet for .worktree-env.
# If not, offers to install it. Only checks once per session.
worktree_check_shell_rc() {
  # Only prompt interactively
  if [ ! -t 0 ]; then
    return 0
  fi

  local shell_name rc_file snippet_marker
  shell_name="$(basename "$SHELL")"
  snippet_marker="# worktree-env auto-source"

  case "$shell_name" in
    zsh)  rc_file="$HOME/.zshrc" ;;
    bash) rc_file="$HOME/.bashrc" ;;
    fish) rc_file="$HOME/.config/fish/config.fish" ;;
    *)    return 0 ;;  # unsupported shell, skip silently
  esac

  if [ -f "$rc_file" ] && grep -qF "$snippet_marker" "$rc_file"; then
    return 0
  fi

  echo ""
  echo "The worktree script can set up your shell to automatically load"
  echo "worktree environment variables (WORKTREE_PORTS, WORKTREE_TITLE)"
  echo "and display worktree info whenever you open a terminal in a worktree."
  echo ""
  echo "This adds a small snippet to ${rc_file}."
  local p10k_file="$HOME/.p10k.zsh"
  local needs_p10k_change=false
  if [ "$shell_name" = "zsh" ] && grep -q 'POWERLEVEL9K_INSTANT_PROMPT=verbose' "$p10k_file" 2>/dev/null; then
    needs_p10k_change=true
    echo ""
    echo "Note: Powerlevel10k instant prompt is set to 'verbose' in ~/.p10k.zsh."
    echo "This will change it to 'quiet' so worktree info can display on"
    echo "shell startup without triggering a warning."
  fi
  if ! prompt_yn "Set up auto-source for $shell_name?"; then
    return 0
  fi

  if $needs_p10k_change; then
    sed -i '' 's/POWERLEVEL9K_INSTANT_PROMPT=verbose/POWERLEVEL9K_INSTANT_PROMPT=quiet/' "$p10k_file"
    echo "Changed POWERLEVEL9K_INSTANT_PROMPT to quiet in ~/.p10k.zsh."
  fi

  local snippet
  if [ "$shell_name" = "fish" ]; then
    snippet="
$snippet_marker
function __worktree_env_hook --on-variable PWD
    if test -f \$PWD/$WORKTREE_ENV_FILENAME
        source \$PWD/$WORKTREE_ENV_FILENAME
    end
end
if test -f \$PWD/$WORKTREE_ENV_FILENAME
    source \$PWD/$WORKTREE_ENV_FILENAME
end"
  elif [ "$shell_name" = "zsh" ]; then
    snippet="
$snippet_marker
if [ -f \"\$PWD/$WORKTREE_ENV_FILENAME\" ]; then source \"\$PWD/$WORKTREE_ENV_FILENAME\"; fi
chpwd() { [ -f \"\$PWD/$WORKTREE_ENV_FILENAME\" ] && source \"\$PWD/$WORKTREE_ENV_FILENAME\"; }"
  else
    snippet="
$snippet_marker
if [ -f \"\$PWD/$WORKTREE_ENV_FILENAME\" ]; then source \"\$PWD/$WORKTREE_ENV_FILENAME\"; fi"
  fi

  echo "$snippet" >> "$rc_file"
  echo "Added to ${rc_file}."
  echo "Run 'source ${rc_file}' or open a new terminal to activate."
}

# worktree_cleanup_shell_rc
# Offers to remove the auto-source snippet from the user's shell RC file
# and revert POWERLEVEL9K_INSTANT_PROMPT if it was changed.
worktree_cleanup_shell_rc() {
  local shell_name rc_file
  shell_name="$(basename "$SHELL")"
  local snippet_marker="# worktree-env auto-source"

  case "$shell_name" in
    zsh)  rc_file="$HOME/.zshrc" ;;
    bash) rc_file="$HOME/.bashrc" ;;
    fish) rc_file="$HOME/.config/fish/config.fish" ;;
    *)    return 0 ;;
  esac

  local found_snippet=false found_p10k=false
  if [ -f "$rc_file" ] && grep -qF "$snippet_marker" "$rc_file"; then
    found_snippet=true
  fi
  local p10k_file="$HOME/.p10k.zsh"
  if [ "$shell_name" = "zsh" ] && grep -q 'POWERLEVEL9K_INSTANT_PROMPT=quiet' "$p10k_file" 2>/dev/null; then
    found_p10k=true
  fi

  if ! $found_snippet && ! $found_p10k; then
    echo "No shell RC changes to clean up."
    return 0
  fi

  echo ""
  echo "The worktree script added the following to your shell configuration:"
  if $found_snippet; then
    echo "  - Auto-source snippet in ${rc_file}"
  fi
  if $found_p10k; then
    echo "  - POWERLEVEL9K_INSTANT_PROMPT=quiet in ~/.p10k.zsh"
  fi
  if ! prompt_yn "Remove these changes?"; then
    return 0
  fi

  if $found_snippet; then
    if [ "$shell_name" = "fish" ]; then
      # Fish snippet spans from marker to the second "end" after it
      sed -i '' "/$snippet_marker/,/^end$/d" "$rc_file"
    else
      # zsh/bash: delete from the marker line through the next blank line or EOF
      # The snippet is always appended at the end, so delete from marker to EOF
      # then remove any trailing blank lines
      local tmp="${rc_file}.worktree-tmp"
      sed "/$snippet_marker/,\$d" "$rc_file" > "$tmp" && mv "$tmp" "$rc_file"
      # Remove trailing blank lines
      local tmp2="${rc_file}.worktree-tmp2"
      sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$rc_file" > "$tmp2" && mv "$tmp2" "$rc_file"
    fi
    echo "Removed auto-source snippet from ${rc_file}."
  fi

  if $found_p10k; then
    sed -i '' 's/POWERLEVEL9K_INSTANT_PROMPT=quiet/POWERLEVEL9K_INSTANT_PROMPT=verbose/' "$p10k_file"
    echo "Reverted POWERLEVEL9K_INSTANT_PROMPT to verbose in ~/.p10k.zsh."
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
  local wt_name wt_repo
  wt_name="$(basename "$wt_path")"
  wt_repo="$(basename "$(dirname "$wt_path")")"
  echo "Removing worktree at ${wt_name}..."
  # Clean up isolated kubeconfig if it exists
  local wt_kubeconfig="$HOME/.kube/config-${wt_repo}-${wt_name}"
  if [ -f "$wt_kubeconfig" ]; then
    rm -f "$wt_kubeconfig"
    echo "Removed kubeconfig: ${wt_kubeconfig/#$HOME/~}"
  fi
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
# platforms, copies via rsync.
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
  if [ "$(uname -s)" = "Darwin" ]; then
    osascript -e "display alert \"Clone Complete\" message \"Finished cloning files into $(basename "$wt_path").\" buttons {\"OK\"} default button \"OK\"" &>/dev/null &
  fi
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
SHELL_MPROCS_PREF_FILE="/tmp/worktree-shell-mprocs-preference"

# add_worktree_git_exclude <repo-root>
# Adds .vscode/ to .git/info/exclude with markers if not already present.
add_worktree_git_exclude() {
  local repo_root="$1"
  local exclude_file="$repo_root/.git/info/exclude"
  if grep -q "# BEGIN $WORKTREE_EXCLUDE_MARKER" "$exclude_file" 2>/dev/null; then
    # Block exists — check if .worktree-env is already in it
    if ! grep -q '\.worktree-env' "$exclude_file" 2>/dev/null; then
      sed -i '' "/# END $WORKTREE_EXCLUDE_MARKER/i\\
.worktree-env
" "$exclude_file"
    fi
    return
  fi
  mkdir -p "$repo_root/.git/info"
  printf '\n# BEGIN %s\n.vscode/\n.worktree-env\n# END %s\n' "$WORKTREE_EXCLUDE_MARKER" "$WORKTREE_EXCLUDE_MARKER" >> "$exclude_file"
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

  # Check cached preference
  if [ -f "$VSCODE_TASKS_PREF_FILE" ]; then
    local pref
    pref="$(cat "$VSCODE_TASKS_PREF_FILE")"
    if [ "$pref" = "No" ]; then
      return 1
    fi
    # pref is "Yes", fall through to create
  else
    # Ask user
    echo ""
    echo "Would you like VS Code to auto-start the worktree REPL in its terminal?"
    echo "(This creates a .vscode/tasks.json in the worktree, hidden from git status,"
    echo " and cleaned up automatically when the last worktree for this repo is removed)"
    if prompt_yn "Set up auto-REPL task?"; then
      echo "Yes" > "$VSCODE_TASKS_PREF_FILE"
    else
      echo "No" > "$VSCODE_TASKS_PREF_FILE"
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

# detect_editor - Sets EDITOR_CMD to "cursor", "code", or "zed" if detected, empty otherwise.
detect_editor() {
  EDITOR_CMD=""
  if [ -n "${CURSOR_CHANNEL:-}" ] || [[ "${__CFBundleIdentifier:-}" == *cursor* ]]; then
    EDITOR_CMD="cursor"
  elif [ -n "${VSCODE_PID:-}" ] || [ "${TERM_PROGRAM:-}" = "vscode" ]; then
    EDITOR_CMD="code"
  elif [ "${TERM_PROGRAM:-}" = "zed" ] || [ -n "${ZED_TERM:-}" ]; then
    EDITOR_CMD="zed"
  fi
}

# _open_zed <worktree-path> - Open in Zed, prompting for same/new window.
# Uses a separate cache file for the window mode preference.
_open_zed() {
  local wt_path="$1"
  local zed_cache="/tmp/worktree-zed-window-preference"
  local zed_mode=""

  if [ -f "$zed_cache" ]; then
    zed_mode="$(cat "$zed_cache")"
  fi

  if [ -z "$zed_mode" ]; then
    zed_mode="$(prompt_choice "Zed window mode?" "Same window" "New window")"
    if prompt_yn "Remember this choice for future worktrees?"; then
      echo "$zed_mode" > "$zed_cache"
    fi
  fi

  if [ "$zed_mode" = "New window" ]; then
    env -u CLAUDECODE zed -n "$wt_path"
    echo "Opened Zed in a new window."
  else
    env -u CLAUDECODE zed "$wt_path"
    echo "Opened in Zed (same window)."
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
    if [ "$EDITOR_CMD" = "zed" ]; then
      _open_zed "$wt_path"
    else
      env -u CLAUDECODE $EDITOR_CMD --new-window "$wt_path"
      echo "Opened new ${EDITOR_CMD} window."
    fi
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
      "Zed")
        _open_zed "$wt_path"
        return
        ;;
      "None")
        ;;
    esac
  fi

  local choice
  choice="$(prompt_choice "Which editor?" "VS Code" "Cursor" "Zed" "None")"
  case "$choice" in
    "None") echo "Skipping editor."; return ;;
    *)
      if prompt_yn "Remember this choice for future worktrees?"; then
        echo "$choice" > "$cache_file"
      fi
      ;;
  esac
  case "$choice" in
    "VS Code") env -u CLAUDECODE code --new-window "$wt_path" ;;
    "Cursor") env -u CLAUDECODE cursor --new-window "$wt_path" ;;
    "Zed") _open_zed "$wt_path" ;;
  esac
}

# worktree_gather_info <worktree-path> [--simple]
# Gathers worktree metadata into WT_INFO_* variables for use by worktree_show_info.
# With --simple, skips all GitHub and Jira API calls (fast, local-only).
# Sets: WT_INFO_BRANCH, WT_INFO_TRACKING, WT_INFO_PR_NUM, WT_INFO_PR_URL,
#       WT_INFO_PR_TITLE, WT_INFO_PR_AUTHOR, WT_INFO_PR_STATE,
#       WT_INFO_PR_CREATED, WT_INFO_PR_UPDATED, WT_INFO_PR_BODY,
#       WT_INFO_JIRA_ISSUES, WT_INFO_JIRA_HOST, WT_INFO_JIRA_DETAILS
worktree_gather_info() {
  local wt_path="$1"
  local simple=false
  if [ "${2:-}" = "--simple" ]; then simple=true; fi
  local wt_name
  wt_name="$(basename "$wt_path")"

  WT_INFO_BRANCH="$(git -C "$wt_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"
  WT_INFO_TRACKING="$(git -C "$wt_path" rev-parse --abbrev-ref "@{upstream}" 2>/dev/null || true)"
  WT_INFO_PR_NUM=""
  WT_INFO_PR_URL=""
  WT_INFO_PR_TITLE=""
  WT_INFO_PR_AUTHOR=""
  WT_INFO_PR_STATE=""
  WT_INFO_PR_CREATED=""
  WT_INFO_PR_UPDATED=""
  WT_INFO_PR_BODY=""
  WT_INFO_JIRA_ISSUES=""
  WT_INFO_JIRA_HOST=""
  WT_INFO_JIRA_DETAILS=""

  # PR number from directory name (local, fast)
  if [[ "$wt_name" == pr-* ]]; then
    WT_INFO_PR_NUM="$(echo "$wt_name" | sed 's/^pr-\([0-9]*\)-.*/\1/')"
    local remote_url
    remote_url="$(git -C "$wt_path" remote get-url upstream 2>/dev/null || git -C "$wt_path" remote get-url origin 2>/dev/null || true)"
    if [ -n "$remote_url" ]; then
      WT_INFO_PR_URL="$(echo "$remote_url" | sed 's/\.git$//' | sed 's|git@github.com:|https://github.com/|')/pull/${WT_INFO_PR_NUM}"
    fi
  fi

  if ! $simple; then
    # PR detection via GitHub API (slow)
    if [ -z "$WT_INFO_PR_URL" ] && [ "$WT_INFO_BRANCH" != "unknown" ]; then
      local detected_pr_url
      local search_branch="$WT_INFO_BRANCH"
      local search_head_owner=""
      if [ -n "$WT_INFO_TRACKING" ]; then
        local tracking_remote="${WT_INFO_TRACKING%%/*}"
        local tracking_branch="${WT_INFO_TRACKING#*/}"
        if [ "$tracking_branch" != "$WT_INFO_BRANCH" ]; then
          search_branch="$tracking_branch"
        fi
        local tracking_remote_url
        tracking_remote_url="$(git -C "$wt_path" remote get-url "$tracking_remote" 2>/dev/null || true)"
        if [ -n "$tracking_remote_url" ]; then
          search_head_owner="$(echo "$tracking_remote_url" | sed 's/\.git$//' | sed 's|.*github\.com[:/]||' | cut -d/ -f1)"
        fi
      fi

      local head_filter="$search_branch"
      if [ -n "$search_head_owner" ]; then
        head_filter="${search_head_owner}:${search_branch}"
      fi

      detected_pr_url="$(gh pr list --head "$head_filter" --state all --json url --jq '.[0].url' 2>/dev/null || true)"
      if [ -z "$detected_pr_url" ]; then
        local upstream_repo
        upstream_repo="$(git -C "$wt_path" remote get-url upstream 2>/dev/null | sed 's/\.git$//' | sed 's|.*github\.com[:/]||' || true)"
        if [ -n "$upstream_repo" ]; then
          detected_pr_url="$(gh pr list --head "$head_filter" --repo "$upstream_repo" --state all --json url --jq '.[0].url' 2>/dev/null || true)"
          # If owner:branch format didn't match, try branch name alone
          if [ -z "$detected_pr_url" ] && [ "$head_filter" != "$search_branch" ]; then
            detected_pr_url="$(gh pr list --head "$search_branch" --repo "$upstream_repo" --state all --json url --jq '.[0].url' 2>/dev/null || true)"
          fi
        fi
      fi
      if [ -n "$detected_pr_url" ]; then
        WT_INFO_PR_URL="$detected_pr_url"
        WT_INFO_PR_NUM="$(echo "$detected_pr_url" | grep -o '[0-9]*$')"
      fi
    fi

    # PR metadata via GitHub API (slow)
    if [ -n "$WT_INFO_PR_URL" ]; then
      local pr_details
      pr_details="$(gh pr view "$WT_INFO_PR_URL" --json title,author,state,createdAt,updatedAt,body 2>/dev/null || true)"
      if [ -n "$pr_details" ]; then
        WT_INFO_PR_TITLE="$(echo "$pr_details" | python3 -c "import sys,json; print(json.load(sys.stdin).get('title',''))" 2>/dev/null || true)"
        WT_INFO_PR_AUTHOR="$(echo "$pr_details" | python3 -c "import sys,json; print(json.load(sys.stdin).get('author',{}).get('login',''))" 2>/dev/null || true)"
        WT_INFO_PR_STATE="$(echo "$pr_details" | python3 -c "import sys,json; print(json.load(sys.stdin).get('state',''))" 2>/dev/null || true)"
        WT_INFO_PR_CREATED="$(echo "$pr_details" | python3 -c "import sys,json; print(json.load(sys.stdin).get('createdAt',''))" 2>/dev/null || true)"
        WT_INFO_PR_UPDATED="$(echo "$pr_details" | python3 -c "import sys,json; print(json.load(sys.stdin).get('updatedAt',''))" 2>/dev/null || true)"
        WT_INFO_PR_BODY="$(echo "$pr_details" | python3 -c "import sys,json; print(json.load(sys.stdin).get('body',''))" 2>/dev/null || true)"
      fi
    fi
  fi

  worktree_gather_jira_info "$wt_path" "$($simple && echo "--simple")"
}

# worktree_gather_jira_info <worktree-path> [--simple]
# Detects Jira issue keys from branch name, PR title/body, and cached .worktree-env.
# With --simple, skips PR title/body scanning and Jira API enrichment.
# Sets: WT_INFO_JIRA_ISSUES, WT_INFO_JIRA_HOST, WT_INFO_JIRA_DETAILS
worktree_gather_jira_info() {
  local wt_path="$1"
  local simple=false
  if [ "${2:-}" = "--simple" ]; then simple=true; fi

  # Load Jira config (once per session)
  if [ -z "${_WORKTREE_JIRA_ENV_LOADED:-}" ]; then
    _WORKTREE_JIRA_ENV_LOADED=1
    local lib_dir
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    WORK_SCRIPTS_DIR="${lib_dir%/lib}"
    # shellcheck source=load-env.sh
    source "$lib_dir/load-env.sh" 2>/dev/null
  fi

  if [ -z "${JIRA_PROJECTS:-}" ]; then
    return
  fi

  WT_INFO_JIRA_HOST="${JIRA_HOST:-}"

  # Build grep pattern from JIRA_PROJECTS (e.g. RHOAIENG,RHOAI → (RHOAIENG|RHOAI)-[0-9]+)
  local jira_pattern
  jira_pattern="($(echo "$JIRA_PROJECTS" | tr ',' '|'))-[0-9]+"

  local found_issues=""

  # Check .worktree-env for cached manual associations
  local env_file="${wt_path}/.worktree-env"
  if [ -f "$env_file" ]; then
    local cached
    cached="$(grep '^export WORKTREE_JIRA_ISSUES=' "$env_file" 2>/dev/null | sed 's/^export WORKTREE_JIRA_ISSUES="//' | sed 's/"$//' || true)"
    if [ -n "$cached" ]; then
      found_issues="$cached"
    fi
  fi

  # Scan branch name
  local branch_matches
  branch_matches="$(echo "$WT_INFO_BRANCH" | grep -oE "$jira_pattern" 2>/dev/null || true)"
  if [ -n "$branch_matches" ]; then
    found_issues="${found_issues:+$found_issues }$branch_matches"
  fi

  # Scan PR title and body (skipped in simple mode — no PR metadata available)
  if ! $simple && [ -n "${WT_INFO_PR_TITLE:-}" ]; then
    local title_matches
    title_matches="$(echo "$WT_INFO_PR_TITLE" | grep -oE "$jira_pattern" 2>/dev/null || true)"
    if [ -n "$title_matches" ]; then
      found_issues="${found_issues:+$found_issues }$title_matches"
    fi
  fi
  if ! $simple && [ -n "${WT_INFO_PR_BODY:-}" ]; then
    local body_stripped
    body_stripped="$(echo "$WT_INFO_PR_BODY" | python3 -c "
import sys, re
print(re.sub(r'<!--.*?-->', '', sys.stdin.read(), flags=re.DOTALL))" 2>/dev/null || echo "$WT_INFO_PR_BODY")"
    local body_matches
    body_matches="$(echo "$body_stripped" | grep -oE "$jira_pattern" 2>/dev/null || true)"
    if [ -n "$body_matches" ]; then
      found_issues="${found_issues:+$found_issues }$body_matches"
    fi
  fi

  # Deduplicate
  if [ -n "$found_issues" ]; then
    WT_INFO_JIRA_ISSUES="$(echo "$found_issues" | tr ' ' '\n' | sort -u | tr '\n' ' ' | sed 's/ $//')"
  fi

  if [ -z "$WT_INFO_JIRA_ISSUES" ]; then
    return
  fi

  # Enrich with Jira API metadata when credentials are available (skipped in simple mode)
  if ! $simple && [ "${JIRA_LOADED:-false}" = "true" ] && [ -n "${JIRA_HOST:-}" ]; then
    local issue_key api_response details_lines=""
    for issue_key in $WT_INFO_JIRA_ISSUES; do
      api_response="$(curl --max-time 5 --silent --fail \
        -u "${JIRA_EMAIL}:${JIRA_TOKEN}" \
        "https://${JIRA_HOST}/rest/api/2/issue/${issue_key}?fields=summary,issuetype,status,assignee,priority" \
        2>/dev/null || true)"
      if [ -n "$api_response" ]; then
        local detail_line
        detail_line="$(echo "$api_response" | python3 -c "
import sys, json
d = json.load(sys.stdin)
f = d.get('fields', {})
summary = f.get('summary', '')
itype = f.get('issuetype', {}).get('name', '')
status = f.get('status', {}).get('name', '')
assignee = f.get('assignee', {}).get('displayName', '') if f.get('assignee') else ''
priority = f.get('priority', {}).get('name', '') if f.get('priority') else ''
print(f'{itype}|{priority}|{status}|{summary}|{assignee}')
" 2>/dev/null || true)"
        if [ -n "$detail_line" ]; then
          details_lines="${details_lines:+${details_lines}
}${issue_key}|${detail_line}"
        fi
      fi
    done
    WT_INFO_JIRA_DETAILS="$details_lines"
  fi
}

# worktree_update_env_jira <worktree-path> <issue-keys>
# Writes or updates the WORKTREE_JIRA_ISSUES line in .worktree-env.
worktree_update_env_jira() {
  local wt_path="$1" issues="$2"
  local env_file="${wt_path}/.worktree-env"
  if [ ! -f "$env_file" ]; then
    echo "export WORKTREE_JIRA_ISSUES=\"${issues}\"" >> "$env_file"
  elif grep -q '^export WORKTREE_JIRA_ISSUES=' "$env_file" 2>/dev/null; then
    sed -i '' "s|^export WORKTREE_JIRA_ISSUES=.*|export WORKTREE_JIRA_ISSUES=\"${issues}\"|" "$env_file"
  else
    echo "export WORKTREE_JIRA_ISSUES=\"${issues}\"" >> "$env_file"
  fi
}

# worktree_jira_emoji <type-or-priority> <value>
# Returns an emoji prefix for Jira issue type or priority.
worktree_jira_emoji() {
  local kind="$1" value="$2"
  case "$kind" in
    type)
      case "$value" in
        Bug)     echo "🐛" ;;
        Story)   echo "📖" ;;
        Task)    echo "✅" ;;
        Epic)    echo "⚡" ;;
        Sub-task) echo "📎" ;;
        *)       echo "📋" ;;
      esac
      ;;
    priority)
      case "$value" in
        Blocker)  echo "🔴" ;;
        Critical) echo "🟠" ;;
        Major)    echo "🟡" ;;
        Normal|Medium) echo "🔵" ;;
        Minor)    echo "🟢" ;;
        Trivial)  echo "⚪" ;;
        *)        echo "⬜" ;;
      esac
      ;;
  esac
}

# worktree_jira_priority_color <priority> <red> <yellow> <green> <blue> <reset>
# Returns the priority text wrapped in an appropriate color.
worktree_jira_priority_color() {
  local value="$1" red="$2" yellow="$3" green="$4" blue="$5" reset="$6"
  case "$value" in
    Blocker|Critical) echo "${red}${value}${reset}" ;;
    Major)            echo "${yellow}${value}${reset}" ;;
    Minor|Trivial)    echo "${green}${value}${reset}" ;;
    *)                echo "${blue}${value}${reset}" ;;
  esac
}

# worktree_jira_status_color <status> <green> <yellow> <cyan> <magenta> <reset>
# Returns the status text wrapped in an appropriate color.
worktree_jira_status_color() {
  local value="$1" green="$2" yellow="$3" cyan="$4" magenta="$5" reset="$6"
  case "$value" in
    Done|Closed|Resolved) echo "${green}${value}${reset}" ;;
    "In Progress"|"In Review"|"Code Review") echo "${yellow}${value}${reset}" ;;
    "To Do"|New|Open|Backlog) echo "${cyan}${value}${reset}" ;;
    *)                    echo "${magenta}${value}${reset}" ;;
  esac
}

# worktree_show_environment <worktree-ports> <cyan> <reset>
# Displays the Environment section with worktree-related env vars.
worktree_show_environment() {
  local worktree_ports="$1" cyan="$2" reset="$3"
  echo "${cyan}Environment:${reset}"
  if [ -n "$worktree_ports" ]; then
    echo "  WORKTREE_PORTS=${worktree_ports}"
  fi
  if [ -n "${KUBECONFIG:-}" ]; then
    echo "  KUBECONFIG=${KUBECONFIG/#$HOME/~}"
  fi
  if command -v oc >/dev/null 2>&1; then
    local oc_context
    oc_context="$(oc config current-context 2>/dev/null || true)"
    if [ -n "$oc_context" ]; then
      echo "${cyan}Cluster:${reset} ${oc_context}"
    fi
  fi
}

# worktree_show_info <worktree-path> [show-path] [worktree-ports] [--simple]
# Displays worktree info using WT_INFO_* variables set by worktree_gather_info.
# With --simple, shows only IDs/links (no titles/metadata) and no path.
worktree_show_info() {
  local wt_path="$1"
  local show_path="${2:-true}"
  local worktree_ports="${3:-}"
  local simple=false
  if [ "${4:-}" = "--simple" ]; then simple=true; fi

  local blue cyan green magenta red yellow bold underline reset
  blue="$(tput setaf 12 2>/dev/null || true)"
  cyan="$(tput setaf 6 2>/dev/null || true)"
  green="$(tput setaf 2 2>/dev/null || true)"
  magenta="$(tput setaf 5 2>/dev/null || true)"
  red="$(tput setaf 1 2>/dev/null || true)"
  yellow="$(tput setaf 3 2>/dev/null || true)"
  bold="$(tput bold 2>/dev/null || true)"
  underline="$(tput smul 2>/dev/null || true)"
  reset="$(tput sgr0 2>/dev/null || true)"

  if [ "$show_path" = "true" ]; then
    echo "${cyan}Path:${reset} $(short_path "$wt_path")"
  fi
  echo "${cyan}Branch:${reset} ${WT_INFO_BRANCH}"
  if $simple; then
    worktree_show_environment "${worktree_ports:-}" "$cyan" "$reset"
    return
  fi
  if [ -n "${WT_INFO_PR_NUM:-}" ]; then
    local pr_link="${cyan}PR #${WT_INFO_PR_NUM}${reset}"
    if [ -n "${WT_INFO_PR_URL:-}" ]; then
      pr_link="\033]8;;${WT_INFO_PR_URL}\033\\${underline}${cyan}PR #${WT_INFO_PR_NUM}${reset}\033]8;;\033\\"
    fi
    if $simple; then
      printf "${pr_link}\n"
    else
      echo ""
      local state_display=""
      case "${WT_INFO_PR_STATE:-}" in
        OPEN)   state_display=" ${green}(open)${reset}" ;;
        MERGED) state_display=" ${magenta}(merged)${reset}" ;;
        CLOSED) state_display=" ${red}(closed)${reset}" ;;
      esac
      printf "${pr_link}${state_display}${WT_INFO_PR_TITLE:+: ${WT_INFO_PR_TITLE}}\n"
      if [ -n "${WT_INFO_PR_AUTHOR:-}" ]; then
        echo "  ${cyan}Author:${reset} ${WT_INFO_PR_AUTHOR}"
      fi
      if [ -n "${WT_INFO_PR_CREATED:-}" ]; then
        echo "  ${cyan}Created:${reset} $(relative_time "$WT_INFO_PR_CREATED")"
      fi
      if [ -n "${WT_INFO_PR_UPDATED:-}" ]; then
        echo "  ${cyan}Updated:${reset} $(relative_time "$WT_INFO_PR_UPDATED")"
      fi
      echo ""
    fi
  fi
  if [ -n "${WT_INFO_JIRA_ISSUES:-}" ]; then
    if $simple; then
      local jira_key
      for jira_key in $WT_INFO_JIRA_ISSUES; do
        local jira_link="${bold}${jira_key}${reset}"
        if [ -n "${WT_INFO_JIRA_HOST:-}" ]; then
          jira_link="\033]8;;https://${WT_INFO_JIRA_HOST}/browse/${jira_key}\033\\${underline}${bold}${jira_key}${reset}\033]8;;\033\\"
        fi
        printf "${cyan}Jira:${reset} ${jira_link}\n"
      done
    elif [ "$(echo "$WT_INFO_JIRA_ISSUES" | wc -w | tr -d ' ')" -eq 1 ]; then
      local jira_key="$WT_INFO_JIRA_ISSUES"
      local jira_detail_line=""
      if [ -n "${WT_INFO_JIRA_DETAILS:-}" ]; then
        jira_detail_line="$(echo "$WT_INFO_JIRA_DETAILS" | grep "^${jira_key}|" || true)"
      fi
      if [ -n "$jira_detail_line" ]; then
        local j_type j_priority j_status j_summary j_assignee
        j_type="$(echo "$jira_detail_line" | cut -d'|' -f2)"
        j_priority="$(echo "$jira_detail_line" | cut -d'|' -f3)"
        j_status="$(echo "$jira_detail_line" | cut -d'|' -f4)"
        j_summary="$(echo "$jira_detail_line" | cut -d'|' -f5)"
        j_assignee="$(echo "$jira_detail_line" | cut -d'|' -f6)"
        local type_emoji priority_emoji priority_colored status_colored
        type_emoji="$(worktree_jira_emoji type "$j_type")"
        priority_emoji="$(worktree_jira_emoji priority "$j_priority")"
        priority_colored="$(worktree_jira_priority_color "$j_priority" "$red" "$yellow" "$green" "$blue" "$reset")"
        status_colored="$(worktree_jira_status_color "$j_status" "$green" "$yellow" "$cyan" "$magenta" "$reset")"
        local jira_link="${bold}${jira_key}${reset}"
        if [ -n "${WT_INFO_JIRA_HOST:-}" ]; then
          jira_link="\033]8;;https://${WT_INFO_JIRA_HOST}/browse/${jira_key}\033\\${underline}${bold}${jira_key}${reset}\033]8;;\033\\"
        fi
        printf "${cyan}Jira:${reset} ${jira_link} ${type_emoji}${j_type} ${priority_emoji}${priority_colored} (${status_colored})${j_summary:+: ${j_summary}}\n"
        if [ -n "$j_assignee" ]; then
          echo "  ${cyan}Assignee:${reset} ${j_assignee}"
        fi
      else
        local jira_link="${bold}${jira_key}${reset}"
        if [ -n "${WT_INFO_JIRA_HOST:-}" ]; then
          jira_link="\033]8;;https://${WT_INFO_JIRA_HOST}/browse/${jira_key}\033\\${underline}${bold}${jira_key}${reset}\033]8;;\033\\"
        fi
        printf "${cyan}Jira:${reset} ${jira_link}\n"
      fi
    else
      echo "${cyan}Jira issues:${reset}"
      local jira_key
      for jira_key in $WT_INFO_JIRA_ISSUES; do
        local jira_detail_line=""
        if [ -n "${WT_INFO_JIRA_DETAILS:-}" ]; then
          jira_detail_line="$(echo "$WT_INFO_JIRA_DETAILS" | grep "^${jira_key}|" || true)"
        fi
        if [ -n "$jira_detail_line" ]; then
          local j_type j_priority j_status j_summary j_assignee
          j_type="$(echo "$jira_detail_line" | cut -d'|' -f2)"
          j_priority="$(echo "$jira_detail_line" | cut -d'|' -f3)"
          j_status="$(echo "$jira_detail_line" | cut -d'|' -f4)"
          j_summary="$(echo "$jira_detail_line" | cut -d'|' -f5)"
          j_assignee="$(echo "$jira_detail_line" | cut -d'|' -f6)"
          local type_emoji priority_emoji priority_colored status_colored
          type_emoji="$(worktree_jira_emoji type "$j_type")"
          priority_emoji="$(worktree_jira_emoji priority "$j_priority")"
          priority_colored="$(worktree_jira_priority_color "$j_priority" "$red" "$yellow" "$green" "$blue" "$reset")"
          status_colored="$(worktree_jira_status_color "$j_status" "$green" "$yellow" "$cyan" "$magenta" "$reset")"
          local jira_link="${bold}${jira_key}${reset}"
          if [ -n "${WT_INFO_JIRA_HOST:-}" ]; then
            jira_link="\033]8;;https://${WT_INFO_JIRA_HOST}/browse/${jira_key}\033\\${underline}${bold}${jira_key}${reset}\033]8;;\033\\"
          fi
          printf "  ${jira_link} ${type_emoji}${j_type} ${priority_emoji}${priority_colored} (${status_colored}): ${j_summary}  [${j_assignee:-unassigned}]\n"
        else
          local jira_link="${bold}${jira_key}${reset}"
          if [ -n "${WT_INFO_JIRA_HOST:-}" ]; then
            jira_link="\033]8;;https://${WT_INFO_JIRA_HOST}/browse/${jira_key}\033\\${underline}${bold}${jira_key}${reset}\033]8;;\033\\"
          fi
          printf "  ${jira_link}\n"
        fi
      done
    fi
    if ! $simple; then echo ""; fi
  fi
  if [ -n "${WT_INFO_TRACKING:-}" ]; then
    local info_ahead info_behind info_parts=""
    info_ahead="$(git -C "$wt_path" rev-list --count "${WT_INFO_TRACKING}..HEAD" 2>/dev/null || echo 0)"
    info_behind="$(git -C "$wt_path" rev-list --count "HEAD..${WT_INFO_TRACKING}" 2>/dev/null || echo 0)"
    if [ "$info_ahead" -eq 0 ] && [ "$info_behind" -eq 0 ]; then
      echo "${cyan}Tracking:${reset} up to date with ${WT_INFO_TRACKING}"
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
      echo "${cyan}Tracking:${reset} ${info_parts} ${WT_INFO_TRACKING}"
    fi
  fi
  if [ -z "$(git -C "$wt_path" status --short)" ]; then
    echo "${cyan}Git status:${reset} working tree clean"
  else
    echo "${cyan}Git status:${reset}"
    git -C "$wt_path" status --short
  fi
  worktree_show_environment "${worktree_ports:-}" "$cyan" "$reset"
}

# worktree_repl <repo-root> <worktree-path> [scripts-dir] [--open]
# Interactive loop offering shell, open, cleanup, and exit commands.
worktree_repl() {
  local repo_root="$1" wt_path="$2" scripts_dir="${3:-}"
  local open_editor=false
  if [ "${4:-}" = "--open" ]; then
    open_editor=true
  fi
  local wt_name wt_port_key branch tracking pr_num pr_url
  wt_name="$(basename "$wt_path")"
  # Port range key includes project dir to avoid cross-repo collisions
  wt_port_key="${wt_path#"$WORKTREES_BASE"/}"

  clear
  worktree_gather_info "$wt_path"
  branch="$WT_INFO_BRANCH"
  tracking="$WT_INFO_TRACKING"
  pr_num="$WT_INFO_PR_NUM"
  pr_url="$WT_INFO_PR_URL"
  local pr_title="$WT_INFO_PR_TITLE"
  local pr_author="$WT_INFO_PR_AUTHOR"
  local pr_state="$WT_INFO_PR_STATE"
  local pr_created="$WT_INFO_PR_CREATED"
  local pr_updated="$WT_INFO_PR_UPDATED"
  local jira_issues="$WT_INFO_JIRA_ISSUES"
  local jira_host="$WT_INFO_JIRA_HOST"
  local jira_details="$WT_INFO_JIRA_DETAILS"

  # --- Open editor (detects editor and sets up auto-REPL task internally) ---
  echo ""
  if $open_editor; then
    open_editor "$wt_path" "$repo_root"
  fi

  local blue cyan green magenta red reset
  blue="$(tput setaf 12 2>/dev/null || true)"
  cyan="$(tput setaf 6 2>/dev/null || true)"
  green="$(tput setaf 2 2>/dev/null || true)"
  magenta="$(tput setaf 5 2>/dev/null || true)"
  red="$(tput setaf 1 2>/dev/null || true)"
  reset="$(tput sgr0 2>/dev/null || true)"

  _worktree_info() {
    local show_path="${1:-true}"
    local worktree_ports="${worktree_ports:-}"
    worktree_gather_info "$wt_path"
    pr_num="$WT_INFO_PR_NUM"
    pr_url="$WT_INFO_PR_URL"
    pr_title="$WT_INFO_PR_TITLE"
    pr_author="$WT_INFO_PR_AUTHOR"
    pr_state="$WT_INFO_PR_STATE"
    pr_created="$WT_INFO_PR_CREATED"
    pr_updated="$WT_INFO_PR_UPDATED"
    jira_issues="$WT_INFO_JIRA_ISSUES"
    jira_host="$WT_INFO_JIRA_HOST"
    jira_details="$WT_INFO_JIRA_DETAILS"
    worktree_show_info "$wt_path" "$show_path" "$worktree_ports"
  }

  _worktree_commands() {
    local W=10 line1 line2 line3
    line1="$(printf "%-${W}s %-${W}s %-${W}s " "[h]elp" "[i]nfo" "[l]og")"
    line1+="[q]uit"

    line2=""
    if [ -n "$scripts_dir" ]; then
      line2+="$(printf "%-${W}s " "[f]iles")"
    fi
    line2+="$(printf "%-${W}s " "[p]refs")"
    if { [ -n "${WORKTREE_MPROCS_PANE:-}" ] && [ -n "${MPROCS_SOCKET:-}" ]; } || cmux_is_available; then
      line2+="$(printf "%-${W}s " "[n]ame")"
    fi
    line2+="[d]elete"

    line3="$(printf "%-${W}s %-${W}s %-${W}s " "[e]ditor" "[s]hell" "[c]laude")"
    if [ -n "${pr_url:-}" ]; then
      line3+="$(printf "%-${W}s " "[g]ithub")"
    fi
    line3+="[j]ira"

    echo "${blue}${line1}${reset}"
    echo "${blue}${line2}${reset}"
    echo "${blue}${line3}${reset}"
  }

  _worktree_help() {
    echo ""
    echo "  ${blue}Navigation${reset}"
    echo "    ${blue}h${reset}  help      Show this help"
    echo "    ${blue}i${reset}  info      Show worktree path, git status, PR info, and Jira details"
    echo "    ${blue}l${reset}  log       Show git log"
    echo "    ${blue}q${reset}  quit      Exit the REPL"
    echo ""
    echo "  ${blue}Manage${reset}"
    if [ -n "$scripts_dir" ]; then
      echo "    ${blue}f${reset}  files     Clone gitignored files (dotfiles, dependencies) from the main worktree"
    fi
    echo "    ${blue}p${reset}  prefs     Show saved preferences and optionally clean them up"
    if [ -n "${WORKTREE_MPROCS_PANE:-}" ] && [ -n "${MPROCS_SOCKET:-}" ]; then
      echo "    ${blue}n${reset}  name      Rename this mprocs pane"
    elif cmux_is_available; then
      echo "    ${blue}n${reset}  name      Rename this cmux workspace"
    fi
    echo "    ${blue}d${reset}  delete    Remove the worktree and its branch"
    echo ""
    echo "  ${blue}Open${reset}"
    echo "    ${blue}e${reset}  editor    Open worktree in your editor (focuses existing window if already open)"
    if cmux_is_available; then
      echo "    ${blue}s${reset}  shell     Start a shell in the worktree"
      echo "    ${blue}c${reset}  claude    Start Claude Code in the worktree"
    else
      echo "    ${blue}s${reset}  shell     Start a shell in the worktree (mprocs with worktree REPL + shell pane)"
      echo "    ${blue}c${reset}  claude    Start Claude Code in the worktree (adds pane to mprocs session)"
    fi
    if [ -n "${pr_url:-}" ]; then
      echo "    ${blue}g${reset}  github    Open the pull request page on GitHub"
    fi
    echo "    ${blue}j${reset}  jira      Open associated Jira issue in browser"
  }

  # Assign port range for this worktree
  local worktree_ports
  worktree_ports="$(assign_port_range "$wt_port_key")"

  # Set iTerm2 tab title and WORKTREE_TITLE
  local worktree_title iterm_label=""
  worktree_title="wt ${branch}"
  # Write .worktree-env file for auto-sourcing by shell RC
  worktree_write_env_file "$wt_path" "$worktree_ports" "$worktree_title"
  worktree_check_shell_rc

  if cmux_is_available; then
    cmux rename-workspace "$worktree_title" >/dev/null 2>&1
  elif [ "$TERM_PROGRAM" = "iTerm.app" ]; then
    iterm_label="$worktree_title"
    printf '\033]1;%s\007' "$iterm_label"
  fi

  _worktree_info false
  if [ -n "$scripts_dir" ]; then
    echo ""
    echo "Tip: type [f]iles to clone installed dependencies and configuration from the main repo"
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
      i|info)
        echo ""
        _worktree_info
        ;;
      l|log)
        git -C "$wt_path" log --oneline --graph --decorate || true
        ;;
      e|editor)
        open_editor "$wt_path" "$repo_root"
        ;;
      g|github)
        if [ -n "${pr_url:-}" ]; then
          echo "Opening ${pr_url}"
          open "$pr_url"
        else
          echo "No open pull request found for this branch."
        fi
        ;;
      j|jira)
        if [ -z "${JIRA_PROJECTS:-}" ]; then
          echo "Jira integration not configured. Add JIRA_PROJECTS to your jira.env file."
          echo "See: jira.env.example"
        elif [ -z "${jira_issues:-}" ]; then
          echo "No Jira issue detected for this worktree."
          printf "Paste a Jira issue key or URL to associate (or press Enter to skip): "
          read -r jira_input
          if [ -n "$jira_input" ]; then
            local jira_key_input
            jira_key_input="$(echo "$jira_input" | grep -oE "($(echo "$JIRA_PROJECTS" | tr ',' '|'))-[0-9]+" | head -1)"
            if [ -n "$jira_key_input" ]; then
              jira_issues="$jira_key_input"
              jira_host="${JIRA_HOST:-}"
              worktree_update_env_jira "$wt_path" "$jira_issues"
              echo "Associated ${jira_key_input} with this worktree."
              if [ -n "$jira_host" ]; then
                local jira_url="https://${jira_host}/browse/${jira_key_input}"
                echo "Opening ${jira_url}"
                open "$jira_url"
              fi
            else
              echo "Could not find a matching Jira issue key (expected projects: ${JIRA_PROJECTS})."
            fi
          fi
        else
          local jira_issue_count
          jira_issue_count="$(echo "$jira_issues" | wc -w | tr -d ' ')"
          if [ "$jira_issue_count" -eq 1 ]; then
            local jira_url="https://${jira_host}/browse/${jira_issues}"
            echo "Opening ${jira_url}"
            open "$jira_url"
          else
            echo ""
            echo "Multiple Jira issues found:"
            local idx=1 jira_key
            for jira_key in $jira_issues; do
              local detail_line=""
              if [ -n "${jira_details:-}" ]; then
                detail_line="$(echo "$jira_details" | grep "^${jira_key}|" || true)"
              fi
              if [ -n "$detail_line" ]; then
                local j_type j_summary
                j_type="$(echo "$detail_line" | cut -d'|' -f2)"
                j_summary="$(echo "$detail_line" | cut -d'|' -f5)"
                local type_emoji
                type_emoji="$(worktree_jira_emoji type "$j_type")"
                echo "  ${idx}) ${jira_key} ${type_emoji}${j_type}: ${j_summary}"
              else
                echo "  ${idx}) ${jira_key}"
              fi
              idx=$((idx + 1))
            done
            printf "\nSelect issue number (or press Enter to skip): "
            read -r jira_selection
            if [ -n "$jira_selection" ] && [ "$jira_selection" -ge 1 ] 2>/dev/null && [ "$jira_selection" -lt "$idx" ] 2>/dev/null; then
              local selected_key
              selected_key="$(echo "$jira_issues" | tr ' ' '\n' | sed -n "${jira_selection}p")"
              if [ -n "$selected_key" ] && [ -n "$jira_host" ]; then
                local jira_url="https://${jira_host}/browse/${selected_key}"
                echo "Opening ${jira_url}"
                open "$jira_url"
              fi
            fi
          fi
        fi
        ;;
      c|claude)
        if cmux_is_available; then
          echo "Starting Claude in $(short_path "$wt_path")"
          echo "Exit Claude to return to this REPL."
          (cd "$wt_path" && claude)
          echo ""
          echo "Back in worktree REPL."
          _worktree_info
        elif [ -n "${WORKTREE_SHELL_MPROCS_SOCK:-}" ]; then
          local claude_count_file="/tmp/worktree-shell-mprocs-${WORKTREE_SHELL_MPROCS_PID:-unknown}-count"
          if [ ! -f "$claude_count_file" ]; then
            echo 2 > "$claude_count_file"
          fi
          mprocs --server "$WORKTREE_SHELL_MPROCS_SOCK" --ctl "{c: add-proc, cmd: \"cd '$wt_path' && claude\", name: \"[claude]\"}"
          local claude_current
          claude_current="$(cat "$claude_count_file")"
          echo "$((claude_current + 1))" > "$claude_count_file"
          sleep 0.3
          local claude_new_idx
          claude_new_idx="$(cat "$claude_count_file")"
          mprocs --server "$WORKTREE_SHELL_MPROCS_SOCK" --ctl "{c: select-proc, index: $((claude_new_idx - 1))}"
          echo "Added [claude] pane."
        elif command -v mprocs &>/dev/null; then
          local use_mprocs_c=""
          if [ -f "$SHELL_MPROCS_PREF_FILE" ]; then
            use_mprocs_c="$(cat "$SHELL_MPROCS_PREF_FILE")"
          else
            echo ""
            echo "The claude command can start a nested mprocs session with a [worktree] pane"
            echo "and a [claude] pane. You can add more panes later with [s]hell."
            if prompt_yn "Use nested mprocs for shell sessions?"; then
              use_mprocs_c="yes"
            else
              use_mprocs_c="no"
            fi
            echo "$use_mprocs_c" > "$SHELL_MPROCS_PREF_FILE"
          fi

          if [ "$use_mprocs_c" = "yes" ]; then
            local claude_mprocs_id="$$-$(date +%s)"
            local claude_mprocs_cfg="/tmp/worktree-shell-mprocs-${claude_mprocs_id}.yaml"
            local claude_mprocs_port
            claude_mprocs_port=$((19200 + (RANDOM % 800)))
            while lsof -i ":${claude_mprocs_port}" &>/dev/null; do
              claude_mprocs_port=$((19200 + (RANDOM % 800)))
            done
            local claude_mprocs_sock="127.0.0.1:${claude_mprocs_port}"
            local claude_mprocs_count="/tmp/worktree-shell-mprocs-${claude_mprocs_id}-count"
            local claude_self_cmd
            claude_self_cmd="$(command -v worktree)"
            rm -f "$claude_mprocs_cfg" "$claude_mprocs_count"
            echo 2 > "$claude_mprocs_count"
            local claude_cfg_content
            claude_cfg_content="hide_keymap_window: true
proc_list_title: \"$worktree_title\"
procs:
  \"[worktree]\":
    shell: \"(sleep 0.5 && mprocs --server '$claude_mprocs_sock' --ctl '{c: select-proc, index: 1}') & $claude_self_cmd '$wt_path'\"
    env:
      WORKTREE_MPROCS_PANE: \"1\"
      MPROCS_SOCKET: \"$claude_mprocs_sock\"
      WORKTREE_SHELL_MPROCS_SOCK: \"$claude_mprocs_sock\"
      WORKTREE_SHELL_MPROCS_PID: \"$claude_mprocs_id\"
  \"[claude]\":
    shell: \"cd '$wt_path' && claude\"
    env:
      WORKTREE_SHELL_MPROCS_SOCK: \"$claude_mprocs_sock\"
      WORKTREE_SHELL_MPROCS_PID: \"$claude_mprocs_id\""
            echo "$claude_cfg_content" > "$claude_mprocs_cfg"
            echo "Starting mprocs session with Claude..."
            env -u MPROCS_SOCKET mprocs --config "$claude_mprocs_cfg" --server "$claude_mprocs_sock" || true
            rm -f "$claude_mprocs_cfg" "$claude_mprocs_count"
            echo ""
            echo "Back in worktree REPL."
            if [ -n "$iterm_label" ]; then
              printf '\033]1;%s\007' "$iterm_label"
            fi
            _worktree_info
          else
            echo "Starting Claude in $(short_path "$wt_path")"
            echo "Exit Claude to return to this REPL."
            (cd "$wt_path" && claude)
            echo ""
            echo "Back in worktree REPL."
            if [ -n "$iterm_label" ]; then
              printf '\033]1;%s\007' "$iterm_label"
            fi
            _worktree_info
          fi
        else
          echo "Starting Claude in $(short_path "$wt_path")"
          echo "Exit Claude to return to this REPL."
          (cd "$wt_path" && claude)
          echo ""
          echo "Back in worktree REPL."
          if [ -n "$iterm_label" ]; then
            printf '\033]1;%s\007' "$iterm_label"
          fi
          _worktree_info
        fi
        ;;
      s|shell)
        local shell_name
        shell_name="$(basename "$SHELL")"

        if cmux_is_available; then
          echo "Starting shell in $(short_path "$wt_path")"
          echo "Exit the shell to return to this REPL."
          (cd "$wt_path" && WORKTREE_PORTS="$worktree_ports" WORKTREE_TITLE="$worktree_title" "$SHELL")
          echo ""
          echo "Back in worktree REPL."
          _worktree_info
        elif [ -n "${WORKTREE_SHELL_MPROCS_SOCK:-}" ]; then
          local shell_count_file="/tmp/worktree-shell-mprocs-${WORKTREE_SHELL_MPROCS_PID:-unknown}-count"
          if [ ! -f "$shell_count_file" ]; then
            echo 2 > "$shell_count_file"
          fi
          local motd="$scripts_dir/mprocs-motd.sh"
          mprocs --server "$WORKTREE_SHELL_MPROCS_SOCK" --ctl "{c: add-proc, cmd: \"$motd && cd '$wt_path' && WORKTREE_PORTS='$worktree_ports' WORKTREE_TITLE='$worktree_title' WORKTREE_SHELL_MPROCS_SOCK='$WORKTREE_SHELL_MPROCS_SOCK' WORKTREE_SHELL_MPROCS_PID='${WORKTREE_SHELL_MPROCS_PID:-}' exec $SHELL\", name: \"[$shell_name]\"}"
          local current_count
          current_count="$(cat "$shell_count_file")"
          echo "$((current_count + 1))" > "$shell_count_file"
          sleep 0.3
          local new_idx
          new_idx="$(cat "$shell_count_file")"
          mprocs --server "$WORKTREE_SHELL_MPROCS_SOCK" --ctl "{c: select-proc, index: $((new_idx - 1))}"
          echo "Added [$shell_name] pane."
        elif command -v mprocs &>/dev/null; then
          # Check preference for nested mprocs
          local use_mprocs=""
          if [ -f "$SHELL_MPROCS_PREF_FILE" ]; then
            use_mprocs="$(cat "$SHELL_MPROCS_PREF_FILE")"
          else
            echo ""
            echo "The shell command can start a nested mprocs session with a [worktree] pane"
            echo "(running this REPL) and a [$shell_name] pane. You can add more shell panes later."
            if prompt_yn "Use nested mprocs for shell sessions?"; then
              use_mprocs="yes"
            else
              use_mprocs="no"
            fi
            echo "$use_mprocs" > "$SHELL_MPROCS_PREF_FILE"
          fi

          if [ "$use_mprocs" = "yes" ]; then
            local shell_mprocs_id="$$-$(date +%s)"
            local shell_mprocs_cfg="/tmp/worktree-shell-mprocs-${shell_mprocs_id}.yaml"
            local shell_mprocs_port
            shell_mprocs_port=$((19200 + (RANDOM % 800)))
            while lsof -i ":${shell_mprocs_port}" &>/dev/null; do
              shell_mprocs_port=$((19200 + (RANDOM % 800)))
            done
            local shell_mprocs_sock="127.0.0.1:${shell_mprocs_port}"
            local shell_mprocs_count="/tmp/worktree-shell-mprocs-${shell_mprocs_id}-count"
            local self_cmd
            self_cmd="$(command -v worktree)"
            local motd="$scripts_dir/mprocs-motd.sh"
            rm -f "$shell_mprocs_cfg" "$shell_mprocs_count"
            echo 2 > "$shell_mprocs_count"
            local shell_cfg_content
            shell_cfg_content="hide_keymap_window: true
proc_list_title: \"$worktree_title\"
procs:
  \"[worktree]\":
    shell: \"(sleep 0.5 && mprocs --server '$shell_mprocs_sock' --ctl '{c: select-proc, index: 1}') & $self_cmd '$wt_path'\"
    env:
      WORKTREE_MPROCS_PANE: \"1\"
      MPROCS_SOCKET: \"$shell_mprocs_sock\"
      WORKTREE_SHELL_MPROCS_SOCK: \"$shell_mprocs_sock\"
      WORKTREE_SHELL_MPROCS_PID: \"$shell_mprocs_id\"
  \"[$shell_name]\":
    shell: \"$motd && exec $SHELL\"
    cwd: \"$wt_path\"
    env:
      WORKTREE_PORTS: \"$worktree_ports\"
      WORKTREE_TITLE: \"$worktree_title\"
      WORKTREE_SHELL_MPROCS_SOCK: \"$shell_mprocs_sock\"
      WORKTREE_SHELL_MPROCS_PID: \"$shell_mprocs_id\""
            echo "$shell_cfg_content" > "$shell_mprocs_cfg"
            echo "Starting mprocs shell session..."
            env -u MPROCS_SOCKET mprocs --config "$shell_mprocs_cfg" --server "$shell_mprocs_sock" || true
            rm -f "$shell_mprocs_cfg" "$shell_mprocs_count"
            echo ""
            echo "Back in worktree REPL."
            if [ -n "$iterm_label" ]; then
              printf '\033]1;%s\007' "$iterm_label"
            fi
            _worktree_info
          else
            echo "Starting shell in $(short_path "$wt_path")"
            echo "Exit the shell to return to this REPL."
            (cd "$wt_path" && WORKTREE_PORTS="$worktree_ports" WORKTREE_TITLE="$worktree_title" "$SHELL")
            echo ""
            echo "Back in worktree REPL."
            if [ -n "$iterm_label" ]; then
              printf '\033]1;%s\007' "$iterm_label"
            fi
            _worktree_info
          fi
        else
          echo "Starting shell in $(short_path "$wt_path")"
          echo "Exit the shell to return to this REPL."
          (cd "$wt_path" && WORKTREE_PORTS="$worktree_ports" WORKTREE_TITLE="$worktree_title" "$SHELL")
          echo ""
          echo "Back in worktree REPL."
          if [ -n "$iterm_label" ]; then
            printf '\033]1;%s\007' "$iterm_label"
          fi
          _worktree_info
        fi
        ;;
      f|files)
        if [ -n "$scripts_dir" ]; then
          clone_worktree_files "$scripts_dir" "$repo_root" "$wt_path" || true
        else
          echo "Clone files not available (missing scripts directory)."
        fi
        ;;
      d|delete)
        echo "This will remove the worktree at:"
        echo "  $(short_path "$wt_path")"
        if prompt_yn "Proceed?"; then
          release_port_range "$wt_port_key"
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
      q|quit|exit)
        if [ -n "${WORKTREE_MPROCS_PANE:-}" ]; then
          echo ""
          echo "To close this pane: Ctrl+A → d → y"
        fi
        exit 0
        ;;
      n|name)
        if cmux_is_available; then
          printf "New name (enter to reset): "
          local new_name=""
          read -r new_name
          if [ -z "$new_name" ]; then
            new_name="$worktree_title"
          fi
          cmux rename-workspace "$new_name" >/dev/null 2>&1 \
            && echo "Renamed workspace to: $new_name" \
            || echo "Failed to rename workspace."
        elif [ -n "${WORKTREE_MPROCS_PANE:-}" ] && [ -n "${MPROCS_SOCKET:-}" ]; then
          printf "New name (enter to reset): "
          local new_name=""
          read -r new_name
          if [ -z "$new_name" ]; then
            new_name="${WORKTREE_TITLE:-$worktree_title}"
          fi
          mprocs --server "$MPROCS_SOCKET" --ctl "{c: rename-proc, name: \"$new_name\"}" 2>/dev/null \
            && echo "Renamed to: $new_name" \
            || echo "Failed to rename (mprocs server not reachable)."
        else
          echo "Name command is only available inside mprocs or cmux."
        fi
        ;;
      p|prefs|preferences)
        echo ""
        local p_files=() p_labels=() p_values=()
        if [ -f /tmp/worktree-editor-preference ]; then
          p_files+=("/tmp/worktree-editor-preference")
          p_labels+=("Editor")
          p_values+=("$(cat /tmp/worktree-editor-preference)")
        fi
        if [ -f /tmp/worktree-zed-window-preference ]; then
          p_files+=("/tmp/worktree-zed-window-preference")
          p_labels+=("Zed window mode")
          p_values+=("$(cat /tmp/worktree-zed-window-preference)")
        fi
        if [ -f "$VSCODE_TASKS_PREF_FILE" ]; then
          p_files+=("$VSCODE_TASKS_PREF_FILE")
          p_labels+=("VS Code auto-REPL")
          p_values+=("$(cat "$VSCODE_TASKS_PREF_FILE")")
        fi
        if [ -f "$SHELL_MPROCS_PREF_FILE" ]; then
          p_files+=("$SHELL_MPROCS_PREF_FILE")
          p_labels+=("Shell mprocs")
          p_values+=("$(cat "$SHELL_MPROCS_PREF_FILE")")
        fi
        while IFS= read -r f; do
          local p_name
          p_name="$(basename "$f")"
          local p_kind="${p_name#worktree-clone-}"
          p_kind="${p_kind%%-*}"
          local p_repo="${p_name#worktree-clone-${p_kind}-}"
          p_files+=("$f")
          p_labels+=("Clone ${p_kind} for ${p_repo}")
          p_values+=("$(cat "$f" | head -1)")
        done < <(find -L /tmp -maxdepth 1 -name "worktree-clone-*" 2>/dev/null | sort)
        while IFS= read -r f; do
          local p_name
          p_name="$(basename "$f")"
          local p_kind="${p_name#worktree-link-}"
          p_kind="${p_kind%%-*}"
          local p_repo="${p_name#worktree-link-${p_kind}-}"
          p_files+=("$f")
          p_labels+=("Link ${p_kind} for ${p_repo}")
          p_values+=("$(cat "$f" | head -1)")
        done < <(find -L /tmp -maxdepth 1 -name "worktree-link-*" 2>/dev/null | sort)

        if [ ${#p_files[@]} -eq 0 ]; then
          echo "No saved preferences."
        else
          echo "Saved preferences:"
          for i in "${!p_labels[@]}"; do
            echo "  ${blue}${p_labels[$i]}${reset}: ${p_values[$i]}"
          done
          echo ""
          if prompt_yn "Clean up preferences?"; then
            local sel_prefs=()
            while IFS= read -r line; do
              [ -n "$line" ] && sel_prefs+=("$line")
            done <<< "$(prompt_multi_select "Remove which preferences?" "${p_labels[@]}")"
            for sel in "${sel_prefs[@]+${sel_prefs[@]}}"; do
              for i in "${!p_labels[@]}"; do
                if [ "${p_labels[$i]}" = "$sel" ]; then
                  rm -f "${p_files[$i]}"
                  echo "Removed: ${sel}"
                  break
                fi
              done
            done
          fi
        fi
        ;;
      h|help)
        _worktree_help
        ;;
      "")
        ;;
      *)
        echo "Unknown command: $cmd. Type 'h' for help."
        ;;
    esac
  done
}

parse_json() {
  python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('$1',''))" 2>/dev/null
}

# worktree_post_setup <scripts-dir> <repo-root> <worktree-path> [--open]
# Handles starting the REPL after initial worktree creation.
worktree_post_setup() {
  local scripts_dir="$1" repo_root="$2" wt_path="$3"
  worktree_repl "$repo_root" "$wt_path" "$scripts_dir" "${4:-}"
}

# discover_all_worktrees
# Finds all git worktrees across WORKTREE_SEARCH_ROOTS by locating repos and
# querying each for its worktrees. Populates global arrays:
#   disc_wt_paths[]      — absolute path to each worktree
#   disc_wt_branches[]   — branch name (short) for each worktree
#   disc_wt_repos[]      — repo name (for grouping) for each worktree
#   disc_wt_repo_roots[] — main repo root path for each worktree
#   disc_wt_labels[]     — display label for each worktree
#   disc_wt_prunable[]   — "true" if git reports the worktree as prunable
#   disc_repos[]         — unique repo names found (ordered)
discover_all_worktrees() {
  disc_wt_paths=()
  disc_wt_branches=()
  disc_wt_repos=()
  disc_wt_repo_roots=()
  disc_wt_labels=()
  disc_wt_prunable=()
  disc_repos=()

  # Build prune args for find
  local prune_args=()
  local IFS_SAVE="$IFS"
  IFS=':'
  local prune_names
  read -ra prune_names <<< "$WORKTREE_SEARCH_PRUNE"
  IFS="$IFS_SAVE"
  for pname in "${prune_names[@]}"; do
    [ -n "$pname" ] || continue
    if [ ${#prune_args[@]} -eq 0 ]; then
      prune_args=(-name "$pname")
    else
      prune_args+=(-o -name "$pname")
    fi
  done

  # Track seen repo roots to avoid duplicates
  local seen_repos=""

  # Search each root
  IFS=':'
  local search_roots
  read -ra search_roots <<< "$WORKTREE_SEARCH_ROOTS"
  IFS="$IFS_SAVE"

  for search_root in "${search_roots[@]}"; do
    [ -d "$search_root" ] || continue

    # Find .git directories (repos) under this search root
    local find_cmd=(find "$search_root" -maxdepth "$WORKTREE_SEARCH_DEPTH")
    if [ ${#prune_args[@]} -gt 0 ]; then
      find_cmd+=('(' "${prune_args[@]}" ')' -prune -o)
    fi
    find_cmd+=(-name ".git" -type d -print)

    while IFS= read -r gitdir; do
      local repo_path
      repo_path="$(dirname "$gitdir")"

      # Skip if we've already processed this repo
      case "$seen_repos" in
        *"|${repo_path}|"*) continue ;;
      esac
      seen_repos="${seen_repos}|${repo_path}|"

      # Get worktree list for this repo
      local porcelain
      porcelain="$(git -C "$repo_path" worktree list --porcelain 2>/dev/null)" || continue

      # Parse porcelain output: collect all entries, skip the first (main worktree)
      local main_root=""
      local wt_paths_tmp=() wt_branches_tmp=() wt_prunable_tmp=()
      local current_wt="" current_branch="" current_prunable=false
      while IFS= read -r line; do
        case "$line" in
          "worktree "*)
            # Save previous entry
            if [ -n "$current_wt" ]; then
              wt_paths_tmp+=("$current_wt")
              wt_branches_tmp+=("$current_branch")
              wt_prunable_tmp+=("$current_prunable")
            fi
            current_wt="${line#worktree }"
            current_branch=""
            current_prunable=false
            ;;
          "branch refs/heads/"*)
            current_branch="${line#branch refs/heads/}"
            ;;
          "prunable "*)
            current_prunable=true
            ;;
        esac
      done <<< "$porcelain"
      # Save last entry
      if [ -n "$current_wt" ]; then
        wt_paths_tmp+=("$current_wt")
        wt_branches_tmp+=("$current_branch")
        wt_prunable_tmp+=("$current_prunable")
      fi

      # First entry is the main worktree; skip it, emit the rest
      [ ${#wt_paths_tmp[@]} -gt 1 ] || continue
      main_root="${wt_paths_tmp[0]}"
      local j
      for j in "${!wt_paths_tmp[@]}"; do
        [ "$j" -eq 0 ] && continue
        _disc_add_worktree "$main_root" "${wt_paths_tmp[$j]}" "${wt_branches_tmp[$j]}" "${wt_prunable_tmp[$j]}"
      done
    done < <("${find_cmd[@]}" 2>/dev/null)
  done
}

_disc_add_worktree() {
  local main_root="$1" wt_path="$2" branch="$3" prunable="$4"
  local repo_name
  repo_name="$(basename "$main_root")"

  # Build display label
  local wt_name
  wt_name="$(basename "$wt_path")"
  local label="$wt_name"
  if [ -n "$branch" ]; then
    label="$branch"
    # Append dir name if it differs from both the branch and the repo name
    if [ "$wt_name" != "$branch" ] && [ "$wt_name" != "$(echo "$branch" | tr '/' '-')" ] && [ "$wt_name" != "$repo_name" ]; then
      label="$branch ($wt_name)"
    fi
  fi
  if [ "$prunable" = "true" ]; then
    label="$label (prunable)"
  elif [ ! -d "$wt_path" ]; then
    label="$label (missing)"
  elif [ ! -e "$wt_path/.git" ]; then
    label="$label (orphaned)"
  fi

  disc_wt_paths+=("$wt_path")
  disc_wt_branches+=("$branch")
  disc_wt_repos+=("$repo_name")
  disc_wt_repo_roots+=("$main_root")
  disc_wt_labels+=("$label")
  disc_wt_prunable+=("$prunable")

  # Track unique repos in order
  local already_listed=false
  for r in "${disc_repos[@]+${disc_repos[@]}}"; do
    if [ "$r" = "$repo_name" ]; then
      already_listed=true
      break
    fi
  done
  if ! $already_listed; then
    disc_repos+=("$repo_name")
  fi
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

  # Check for worktree name under any project subdir
  if [ -d "$WORKTREES_BASE" ]; then
    local candidate
    while IFS= read -r candidate; do
      if [ -d "$candidate" ] && [ -e "$candidate/.git" ]; then
        WT_PATH="$candidate"
        return 0
      fi
    done < <(find "$WORKTREES_BASE" -maxdepth 2 -mindepth 2 -type d -name "$arg" 2>/dev/null)
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
      done < <(find "$WORKTREES_BASE" -maxdepth 2 -mindepth 2 -type d -name "pr-${pr_number}-*" 2>/dev/null)
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
    done < <(find "$WORKTREES_BASE" -maxdepth 2 -mindepth 2 -type d -name "${dir_branch}" 2>/dev/null)
  fi

  # Also check git worktree list for the branch (current repo only)
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

  # Fall back to full discovery across all search roots
  discover_all_worktrees
  for i in "${!disc_wt_paths[@]}"; do
    local dwt="${disc_wt_paths[$i]}"
    local dbranch="${disc_wt_branches[$i]}"
    # Match by branch name
    if [ "$dbranch" = "$arg" ]; then
      WT_PATH="$dwt"
      return 0
    fi
    # Match by directory name
    if [ "$(basename "$dwt")" = "$arg" ] || [ "$(basename "$dwt")" = "$dir_branch" ]; then
      WT_PATH="$dwt"
      return 0
    fi
    # Match PR number by directory name pattern
    if [ -n "$pr_number" ] && [[ "$(basename "$dwt")" == pr-${pr_number}-* ]]; then
      WT_PATH="$dwt"
      return 0
    fi
  done

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

  # If we're inside a worktree (not the main clone), resolve to the main clone
  if [ -f "$toplevel/.git" ]; then
    local main_root
    main_root="$(git -C "$toplevel" worktree list --porcelain 2>/dev/null | head -1 | sed 's/^worktree //')"
    if [ -n "$main_root" ] && [ "$main_root" != "$toplevel" ]; then
      toplevel="$main_root"
    fi
  fi

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
