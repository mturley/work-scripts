#!/usr/bin/env bash
# Fork a Claude Code session into a new, independent session.
# Resumes the given session with --fork-session so the original is untouched.
#
# Usage: claude-fork <session-id-or-name> [--name <name>] [claude args...]

set -uo pipefail

usage() {
  echo "Usage: claude-fork <session-id-or-name> [--name <name>] [claude args...]"
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

session="$1"
shift

name=""
extra_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)
      if [[ $# -lt 2 ]]; then
        echo "Error: --name requires a value" >&2
        usage
        exit 1
      fi
      name="$2"
      shift 2
      ;;
    --name=*)
      name="${1#--name=}"
      shift
      ;;
    *)
      extra_args+=("$1")
      shift
      ;;
  esac
done

if [[ -z "$name" ]]; then
  name="${session}-fork"
fi

exec claude --resume "$session" --fork-session --name "$name" ${extra_args[@]+"${extra_args[@]}"}
