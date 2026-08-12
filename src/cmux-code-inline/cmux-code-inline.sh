#!/usr/bin/env bash
# cmux-code-inline - Open the current directory in cmux's inline VS Code by
# reusing an already-running cmux-managed VS Code web server.
# Usage: cmux-code-inline [PATH]
#
# The cmux "Open Current Directory in VS Code (inline)" command palette action
# starts a VS Code `serve-web` server (bound to 127.0.0.1 on a random port, with
# a per-server connection token) and opens it in a cmux browser surface. That
# built-in action is not exposed as a bindable shortcut or CLI command.
#
# This script does NOT start the server. It finds an already-running cmux-managed
# serve-web process, discovers its port + connection token, and opens
# http://127.0.0.1:<port>/?tkn=<token>&folder=<PATH> in a new cmux browser
# surface. The server stays alive as long as cmux keeps it running, so after
# starting it once via the palette, this script can reopen the inline editor at
# any folder without the palette.
#
# If no running server is found, it aborts and tells you to run the palette
# action once to start one, then retry.

set -euo pipefail

TARGET="${1:-.}"

case "${1:-}" in
  -h|--help)
    echo "Usage: cmux-code-inline [PATH]"
    echo ""
    echo "Open PATH (default: current directory) in cmux's inline VS Code by"
    echo "reusing an already-running cmux-managed VS Code serve-web server."
    echo ""
    echo "Requires a serve-web server to already be running. Start one once via"
    echo "the cmux command palette: \"Open Current Directory in VS Code"
    echo "(inline)\". It stays running as long as cmux keeps it alive, after which"
    echo "this script can reopen the inline editor at any folder."
    exit 0
    ;;
esac

if ! command -v cmux >/dev/null 2>&1; then
  echo "cmux-code-inline: 'cmux' not found on PATH." >&2
  exit 1
fi

# Resolve TARGET to an absolute path (serve-web's ?folder= needs an absolute path).
if [ -d "$TARGET" ]; then
  FOLDER="$(cd "$TARGET" && pwd)"
else
  echo "cmux-code-inline: '$TARGET' is not a directory." >&2
  exit 1
fi

abort_no_server() {
  echo "cmux-code-inline: no running cmux VS Code server found." >&2
  echo "" >&2
  echo "Run the cmux command palette action once to start it:" >&2
  echo "  Cmd+Shift+P -> \"Open Current Directory in VS Code (inline)\"" >&2
  echo "" >&2
  echo "The server stays running as long as cmux keeps it alive. Then run this again." >&2
  exit 1
}

# Find cmux-managed serve-web node processes. cmux passes a connection token file
# named cmux-vscode-token-*, which distinguishes its servers from any other
# serve-web instances. Prefer the most recently started one (last in ps output).
PID=""
TOKEN_FILE=""
while IFS= read -r line; do
  [ -z "$line" ] && continue
  pid="$(echo "$line" | awk '{print $1}')"
  # Extract the value after --connection-token-file
  tf="$(echo "$line" | sed -nE 's/.*--connection-token-file[ =]+([^ ]+).*/\1/p')"
  [ -z "$tf" ] && continue
  PID="$pid"
  TOKEN_FILE="$tf"
done <<EOF
$(ps -axo pid=,command= | grep 'server-main\.js' | grep -- '--connection-token-file' | grep 'cmux-vscode-token' | grep -v grep)
EOF

[ -z "$PID" ] && abort_no_server

if [ ! -r "$TOKEN_FILE" ]; then
  echo "cmux-code-inline: found server (pid $PID) but token file is unreadable: $TOKEN_FILE" >&2
  exit 1
fi
TOKEN="$(cat "$TOKEN_FILE")"
if [ -z "$TOKEN" ]; then
  echo "cmux-code-inline: token file is empty: $TOKEN_FILE" >&2
  exit 1
fi

# Discover the listening port for that pid.
PORT="$(lsof -nP -iTCP -sTCP:LISTEN -a -p "$PID" 2>/dev/null \
  | sed -nE 's/.*127\.0\.0\.1:([0-9]+) .*/\1/p' | head -1)"
if [ -z "$PORT" ]; then
  echo "cmux-code-inline: could not find a listening port for server pid $PID." >&2
  abort_no_server
fi

# URL-encode the folder path for the query string.
urlencode() {
  encoded=""
  i=0
  len=${#1}
  while [ "$i" -lt "$len" ]; do
    c="${1:$i:1}"
    case "$c" in
      [a-zA-Z0-9._~/-]) encoded="$encoded$c" ;;
      *) encoded="$encoded$(printf '%%%02X' "'$c")" ;;
    esac
    i=$((i + 1))
  done
  printf '%s' "$encoded"
}
FOLDER_ENC="$(urlencode "$FOLDER")"

URL="http://127.0.0.1:${PORT}/?tkn=${TOKEN}&folder=${FOLDER_ENC}"

# Open in a new cmux browser surface, focused, matching the palette action.
# Do not close the launch tab if this fails.
cmux new-surface --type browser --url "$URL" --focus true

# Close the throwaway tab this ran in. cmux runs command actions in a new tab, so
# without this the launch terminal lingers. Only close when running inside a cmux
# surface; otherwise leave the shell alone. The inline editor opened above, so a
# failure here is non-fatal.
if [ -n "${CMUX_SURFACE_ID:-}" ]; then
  # cmux close-surface defaults to $CMUX_SURFACE_ID and $CMUX_WORKSPACE_ID.
  cmux close-surface || true
fi
