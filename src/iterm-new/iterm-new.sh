#!/usr/bin/env bash
# iterm-new - Open a new iTerm2 tab or split pane and run a command
#
# Usage: iterm-new <mode> [-n name] <command>
#
# Modes:
#   tab      Open a new tab
#   split-v  Split vertically
#   split-h  Split horizontally
#
# Options:
#   -n <name>  Name the tab/pane (defaults to the command)

set -euo pipefail

if [ $# -eq 0 ]; then
  echo "Usage: iterm-new <tab|split-v|split-h> [-n name] <command>"
  exit 1
fi

MODE="$1"
shift

case "$MODE" in
  tab|split-v|split-h) ;;
  *)
    echo "Usage: iterm-new <tab|split-v|split-h> [-n name] <command>"
    echo "Unknown mode: $MODE"
    exit 1
    ;;
esac

PANE_NAME=""
if [ "${1:-}" = "-n" ]; then
  PANE_NAME="$2"
  shift 2
fi

if [ $# -eq 0 ]; then
  echo "Usage: iterm-new <tab|split-v|split-h> [-n name] <command>"
  exit 1
fi

CMD="$*"
DIR="$(pwd)"
PANE_NAME="${PANE_NAME:-$CMD}"

case "$MODE" in
  tab)
    osascript -e "tell application \"iTerm2\" to tell current window
  set newTab to (create tab with default profile)
  tell current session of newTab
    set name to \"$PANE_NAME\"
    write text \"printf '\\\\033]1;$PANE_NAME\\\\007' && cd $DIR && $CMD\"
  end tell
end tell"
    ;;
  split-v)
    osascript -e "tell application \"iTerm2\" to tell current session of current window
  set newSession to (split vertically with default profile)
  tell newSession
    set name to \"$PANE_NAME\"
    write text \"printf '\\\\033]1;$PANE_NAME\\\\007' && cd $DIR && $CMD\"
  end tell
end tell"
    ;;
  split-h)
    osascript -e "tell application \"iTerm2\" to tell current session of current window
  set newSession to (split horizontally with default profile)
  tell newSession
    set name to \"$PANE_NAME\"
    write text \"printf '\\\\033]1;$PANE_NAME\\\\007' && cd $DIR && $CMD\"
  end tell
end tell"
    ;;
esac
