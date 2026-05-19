#!/usr/bin/env bash
# Resume a Claude Code session from any directory.
# Accepts a session ID or a search term to find a session by message content.
#
# Usage: claude-resume <session-id-or-search-term> [claude args...]

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: claude-resume <session-id-or-search-term> [claude args...]"
  exit 1
fi

input="$1"
shift
sessions_dir="$HOME/.claude/projects"

# Determine if input is a session ID or a search term
session_file=""
sid=""

printf "Looking up session..." >&2
session_file=$(find "$sessions_dir" -name "$input.jsonl" 2>/dev/null | head -1)

if [[ -n "$session_file" ]]; then
  printf "\r%*s\r" 30 "" >&2
  sid="$input"
else
  # Not a session ID — treat as search term, let user pick interactively
  printf "\r%*s\r" 30 "" >&2
  sid=$(claude-sessions --pick "$input")

  if [[ -z "$sid" ]]; then
    echo "No session found matching: $input"
    exit 1
  fi

  session_file=$(find "$sessions_dir" -name "$sid.jsonl" 2>/dev/null | head -1)
fi

cwd=$(grep -o '"cwd":"[^"]*"' "$session_file" | head -1 | cut -d'"' -f4)

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
