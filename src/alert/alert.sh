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
