#!/usr/bin/env bash
# alert - Show a macOS alert dialog
#
# Usage: alert [-t title] [-n lines] [message...]
#        <command> | alert [-t title] [-n lines] [message...]
#
# Options:
#   -t <title>  Alert title (default: "Alert")
#   -n <lines>  Lines to show from each end of piped input (default: 5)
#
# If stdin is piped, the first and last few lines of it are included in the
# alert body, with a [...] marker between them when lines are omitted.
#
# Uses osascript's `display alert` (not `display notification`, which is
# unreliable). Blocks until the alert is dismissed.

set -euo pipefail

usage() {
  echo "Usage: alert [-t title] [-n lines] [message...]"
  echo "       <command> | alert [-t title] [-n lines] [message...]"
}

TITLE="Alert"
MAX_LINES=5

while [ $# -gt 0 ]; do
  case "$1" in
    -t|--title)
      if [ $# -lt 2 ]; then
        usage
        exit 1
      fi
      TITLE="$2"
      shift 2
      ;;
    -n|--lines)
      if [ $# -lt 2 ]; then
        usage
        exit 1
      fi
      MAX_LINES="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

case "$MAX_LINES" in
  ''|*[!0-9]*)
    echo "alert: -n expects a number, got: $MAX_LINES" >&2
    exit 1
    ;;
esac

MESSAGE="$*"

# Read piped input, if any. A terminal on stdin means nothing was piped.
if [ ! -t 0 ]; then
  PIPED="$(cat)"
  if [ -n "$PIPED" ]; then
    TOTAL_LINES="$(printf '%s\n' "$PIPED" | wc -l | tr -d ' ')"
    if [ "$TOTAL_LINES" -le $((MAX_LINES * 2)) ]; then
      EXCERPT="$PIPED"
    else
      # awk rather than head: head exits early, which would SIGPIPE the printf
      # and trip pipefail on large input.
      FIRST="$(printf '%s\n' "$PIPED" | awk -v n="$MAX_LINES" 'NR <= n')"
      LAST="$(printf '%s\n' "$PIPED" | tail -n "$MAX_LINES")"
      EXCERPT="$FIRST
[... $((TOTAL_LINES - MAX_LINES * 2)) more lines ...]
$LAST"
    fi
    if [ -n "$MESSAGE" ]; then
      MESSAGE="$MESSAGE

$EXCERPT"
    else
      MESSAGE="$EXCERPT"
    fi
  fi
fi

if [ -z "$MESSAGE" ]; then
  usage
  exit 1
fi

# cmux awareness: cmux terminals export CMUX_WORKSPACE_ID and CMUX_SURFACE_ID
# identifying the surface this command was launched from. Capture them now so
# they pin the *origin* surface even if focus moves while the alert is up.
CMUX_ORIGIN_WORKSPACE="${CMUX_WORKSPACE_ID:-}"
CMUX_ORIGIN_SURFACE="${CMUX_SURFACE_ID:-}"
IN_CMUX=""
if [ -n "$CMUX_ORIGIN_WORKSPACE" ] && [ -n "$CMUX_ORIGIN_SURFACE" ] && command -v cmux >/dev/null 2>&1; then
  IN_CMUX="1"
fi

# When launched from cmux, prefix the title with the origin workspace's title in
# brackets. Requires jq to parse the workspace list; if jq is missing or the
# lookup fails, we skip the prefix rather than error.
if [ -n "$IN_CMUX" ] && command -v jq >/dev/null 2>&1; then
  WORKSPACE_TITLE="$(cmux workspace list --json 2>/dev/null \
    | jq -r --arg id "$CMUX_ORIGIN_WORKSPACE" \
        '.workspaces[]? | select(.id == $id) | .custom_title // empty' \
        2>/dev/null || true)"
  if [ -n "$WORKSPACE_TITLE" ]; then
    TITLE="[$WORKSPACE_TITLE] $TITLE"
  fi
fi

# Pass the strings as argv so quotes/apostrophes in them need no escaping.
# The heredoc becomes osascript's stdin, independent of any input piped above.
osascript - "$TITLE" "$MESSAGE" <<'APPLESCRIPT' >/dev/null
on run argv
  set theTitle to item 1 of argv
  set theMessage to item 2 of argv
  tell application "System Events"
    display alert theTitle message theMessage buttons {"OK"} default button "OK"
  end tell
end run
APPLESCRIPT

# After the alert is acknowledged, if we were launched from cmux, bring cmux to
# the foreground and switch back to the originating workspace and surface. Each
# step is best-effort: a failure here should not leave the user stranded, and
# `set -e` must not abort the script on a non-fatal cmux/osascript hiccup.
if [ -n "$IN_CMUX" ]; then
  osascript -e 'tell application "cmux" to activate' >/dev/null 2>&1 || true
  cmux workspace select --workspace "$CMUX_ORIGIN_WORKSPACE" >/dev/null 2>&1 || true
  cmux focus-panel --panel "$CMUX_ORIGIN_SURFACE" \
    --workspace "$CMUX_ORIGIN_WORKSPACE" >/dev/null 2>&1 || true
fi
