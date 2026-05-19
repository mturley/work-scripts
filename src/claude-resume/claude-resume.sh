#!/usr/bin/env bash
# Resume a Claude Code session from any directory.
# Accepts a session ID or a search term to find a session by message content.
#
# Usage: claude-resume <session-id-or-search-term> [claude args...]

set -uo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: claude-resume <session-id-or-search-term> [claude args...]"
  exit 1
fi

LIB_DIR="$(cd "$(dirname "$(readlink -f "$0")")/../../lib" && pwd)"
source "$LIB_DIR/claude-sessions.sh"

input="$1"
shift

# Check if input is a session ID
printf "Looking up session..." >&2
session_file=$(claude_session_find_file "$input")

if [[ -n "$session_file" ]]; then
  printf "\r%*s\r" 30 "" >&2
  sid="$input"
else
  # Not a session ID — search for it
  printf "\r%*s\r" 30 "" >&2

  if ! claude_sessions_collect; then
    echo "No Claude sessions found."
    exit 1
  fi

  total=${#claude_session_files[@]}
  sid=""

  for (( i = 0; i < total; i++ )); do
    f="${claude_session_files[$i]}"

    printf "\rSearching... [%d/%d]" $((i + 1)) "$total" >&2

    claude_session_parse_search "$f" "$input"

    if [[ "$cs_match" == "true" ]]; then
      printf "\r%*s\r" 50 "" >&2

      claude_session_display "$f" 2

      while true; do
        if ! read -rp "[r]esume this session / [k]eep looking / [a]bort? " choice </dev/tty; then
          exit 1
        fi
        case "$choice" in
          r|R) sid=$(basename "$f" .jsonl); break 2 ;;
          k|K) break ;;
          a|A) exit 1 ;;
          *) echo "Please enter r, k, or a" >&2 ;;
        esac
      done
    fi
  done

  printf "\r%*s\r" 50 "" >&2

  if [[ -z "$sid" ]]; then
    echo "No session found matching: $input"
    exit 1
  fi

  session_file=$(claude_session_find_file "$sid")
fi

cwd=$(claude_session_cwd "$session_file")

if [[ -z "$cwd" ]]; then
  echo "Could not determine working directory for session $sid"
  exit 1
fi

if [[ ! -d "$cwd" ]]; then
  echo "Working directory no longer exists: $cwd"
  exit 1
fi

cd "$cwd"
exec claude --resume "$sid" "$@"
