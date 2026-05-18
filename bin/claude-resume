#!/usr/bin/env bash
# Resume a Claude Code session from any directory.
# Finds the session's working directory and resumes it there.
#
# Usage: claude-resume <session-id>

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: claude-resume <session-id>"
  exit 1
fi

sid="$1"
shift
sessions_dir="$HOME/.claude/projects"

# Find the session file across all projects
session_file=$(find "$sessions_dir" -name "$sid.jsonl" 2>/dev/null | head -1)

if [[ -z "$session_file" ]]; then
  echo "Session not found: $sid"
  exit 1
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
