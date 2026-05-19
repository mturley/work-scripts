#!/usr/bin/env bash
# List Claude Code sessions across all projects, most recent first.
# Shows session ID, working directory, first and last user messages with timestamps.
# Interactive: pages 5 at a time, press Enter for more.
# "text": Search for sessions containing the given text in messages

set -uo pipefail

LIB_DIR="$(cd "$(dirname "$(readlink -f "$0")")/../../lib" && pwd)"
source "$LIB_DIR/claude-sessions.sh"

PAGE_SIZE=5

search_text="${1:-}"

if ! claude_sessions_collect; then
  echo "No Claude sessions found."
  exit 0
fi

total=${#claude_session_files[@]}

if [[ -n "$search_text" ]]; then
  any_match=false
  for (( i = 0; i < total; i++ )); do
    f="${claude_session_files[$i]}"

    printf "\rSearching... [%d/%d]" $((i + 1)) "$total" >&2

    claude_session_parse_search "$f" "$search_text"

    if [[ "$cs_match" == "true" ]]; then
      any_match=true
      printf "\r%*s\r" 50 "" >&2

      claude_session_display "$f"

      if (( i + 1 < total )); then
        read -rp "Enter to keep looking " </dev/tty
      fi
    fi
  done

  printf "\r%*s\r" 50 "" >&2

  if [[ "$any_match" != "true" ]]; then
    echo "No matches found" >&2
    exit 1
  fi
else
  offset=0

  while (( offset < total )); do
    end=$(( offset + PAGE_SIZE ))
    if (( end > total )); then
      end=$total
    fi

    for (( i = offset; i < end; i++ )); do
      f="${claude_session_files[$i]}"
      claude_session_parse "$f"
      claude_session_display "$f"
    done

    offset=$end

    if (( offset < total )); then
      remaining=$(( total - offset ))
      read -rp "[Enter for more ($remaining remaining)] " </dev/tty
    fi
  done
fi
