#!/usr/bin/env bash
# cmux-code - Open VS Code in the current directory, then close the cmux tab it ran in.
# Usage: cmux-code [PATH]
#
# Intended for a cmux command-action hotkey. cmux runs command actions in a new
# tab (surface), so this opens `code` and then closes that throwaway tab. The tab
# is only closed if `code` succeeds, so errors stay visible.

set -euo pipefail

TARGET="${1:-.}"

case "${1:-}" in
  -h|--help)
    echo "Usage: cmux-code [PATH]"
    echo ""
    echo "Runs 'code <PATH>' (default: current directory), then closes the cmux"
    echo "tab it was launched from. Designed for a cmux command-action hotkey."
    echo ""
    echo "The tab is only closed if 'code' succeeds and cmux env vars are present,"
    echo "so failures remain visible."
    exit 0
    ;;
esac

if ! command -v code >/dev/null 2>&1; then
  echo "cmux-code: 'code' command not found on PATH." >&2
  exit 1
fi

# Launch VS Code. Do not close the tab if this fails.
code "$TARGET"

# Only close when running inside cmux; otherwise leave the shell alone.
if ! command -v cmux >/dev/null 2>&1; then
  echo "cmux-code: 'cmux' not found; leaving tab open." >&2
  exit 0
fi

if [[ -z "${CMUX_SURFACE_ID:-}" ]]; then
  echo "cmux-code: not running inside cmux (CMUX_SURFACE_ID unset); leaving tab open." >&2
  exit 0
fi

# Close the calling surface. cmux close-surface defaults to $CMUX_SURFACE_ID and
# $CMUX_WORKSPACE_ID, so no arguments are needed.
cmux close-surface
