#!/usr/bin/env bash
# mprocs-new - Add panes to existing mprocs session or start new mprocs
#
# Usage: mprocs-new <command> [label]
#        mprocs-new <command1> <command2> ...
#
# If called from within an mprocs session, adds panes to that session.
# Otherwise, starts a new mprocs with a shell pane and the specified command pane(s).

set -euo pipefail

if [ $# -eq 0 ]; then
  cat <<'HELPEOF'
Usage: mprocs-new <command> [label]
       mprocs-new <command1> <command2> ...

Add panes to an existing mprocs session or start a new mprocs.

Arguments:
  <command>       Shell command to run in the new pane.
  <label>         Optional label for the pane (defaults to command).

If run from within mprocs (MPROCS_SOCKET set), adds pane(s) to the current session.
Otherwise, starts a new mprocs with a shell pane and the specified command pane(s).

Examples:
  mprocs-new "npm run dev" "dev server"     # add pane with custom label
  mprocs-new "npm test"                     # add pane, label is "npm test"
  mprocs-new "npm run dev" "npm test"       # add two panes

Environment:
  MPROCS_SOCKET   Set by mprocs when running inside a session.
HELPEOF
  exit 0
fi

# Parse arguments into commands and labels
COMMANDS=()
LABELS=()

while [ $# -gt 0 ]; do
  cmd="$1"
  shift
  # If next arg doesn't look like a command (no spaces, slashes, or special chars),
  # treat it as a label for this command
  if [ $# -gt 0 ] && [[ ! "$1" =~ [[:space:]/\$] ]] && [[ ! "$1" == *"="* ]]; then
    label="$1"
    shift
  else
    # Default label is the command itself
    label="$cmd"
  fi
  COMMANDS+=("$cmd")
  LABELS+=("$label")
done

# --- Inside mprocs: add pane(s) to existing session ---
if [ -n "${MPROCS_SOCKET:-}" ]; then
  # Track proc count for enabling select-proc after add
  MPROCS_COUNT_FILE="/tmp/mprocs-new-${MPROCS_SOCKET//[^0-9]/}-count"

  if [ ! -f "$MPROCS_COUNT_FILE" ]; then
    # Initialize count from mprocs config if available
    MPROCS_CFG_FILE="/tmp/mprocs-new-${MPROCS_SOCKET//[^0-9]/}.yaml"
    if [ -f "$MPROCS_CFG_FILE" ]; then
      PROC_COUNT="$(grep -c '^  "' "$MPROCS_CFG_FILE" 2>/dev/null || echo 1)"
    else
      PROC_COUNT=1
    fi
    echo "$PROC_COUNT" > "$MPROCS_COUNT_FILE"
  fi

  for i in "${!COMMANDS[@]}"; do
    cmd="${COMMANDS[$i]}"
    label="${LABELS[$i]}"
    mprocs --server "$MPROCS_SOCKET" --ctl "{c: add-proc, cmd: \"$cmd\", name: \"$label\"}"
    # Increment count
    CURRENT_COUNT="$(cat "$MPROCS_COUNT_FILE")"
    echo "$((CURRENT_COUNT + 1))" > "$MPROCS_COUNT_FILE"
  done

  # If only one pane was added, switch to it
  if [ ${#COMMANDS[@]} -eq 1 ]; then
    sleep 0.3
    NEW_INDEX="$(cat "$MPROCS_COUNT_FILE")"
    mprocs --server "$MPROCS_SOCKET" --ctl "{c: select-proc, index: $((NEW_INDEX - 1))}"
  fi
  exit 0
fi

# --- Not in mprocs: start new mprocs session ---
if ! command -v mprocs &>/dev/null; then
  echo "ERROR: mprocs not found." >&2
  echo "  Install mprocs: brew install mprocs" >&2
  exit 1
fi

MPROCS_CFG="/tmp/mprocs-new-$$.yaml"
MPROCS_SOCK="127.0.0.1:$((19000 + ($$ % 1000)))"
MPROCS_COUNT="/tmp/mprocs-new-$$-count"

rm -f "$MPROCS_CFG" "$MPROCS_COUNT"
trap "rm -f '$MPROCS_CFG' '$MPROCS_COUNT'" EXIT

SHELL_LABEL="[$(basename "$SHELL")]"

echo "procs:" > "$MPROCS_CFG"
echo "  \"$SHELL_LABEL\":" >> "$MPROCS_CFG"
echo "    shell: \"exec $SHELL\"" >> "$MPROCS_CFG"
echo "    cwd: \"$(pwd)\"" >> "$MPROCS_CFG"
echo "    env:" >> "$MPROCS_CFG"
echo "      MPROCS_SOCKET: \"$MPROCS_SOCK\"" >> "$MPROCS_CFG"

for i in "${!COMMANDS[@]}"; do
  cmd="${COMMANDS[$i]}"
  label="${LABELS[$i]}"
  echo "  \"$label\":" >> "$MPROCS_CFG"
  echo "    shell: \"$cmd\"" >> "$MPROCS_CFG"
  echo "    env:" >> "$MPROCS_CFG"
  echo "      MPROCS_SOCKET: \"$MPROCS_SOCK\"" >> "$MPROCS_CFG"
done

# Initialize count file for future mprocs-new calls within this session
echo "$((1 + ${#COMMANDS[@]}))" > "$MPROCS_COUNT_FILE"

exec mprocs --config "$MPROCS_CFG" --server "$MPROCS_SOCK"
