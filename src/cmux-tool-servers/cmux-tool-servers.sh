#!/usr/bin/env bash
# cmux-tool-servers - Run `handler ui` and `worktree ui` side by side in mprocs.
#
# Both agent-handler (`handler ui`) and worktree (`worktree ui`) expose their
# full feature set only when run inside cmux, hence the "cmux" prefix. This
# launches both UIs in a single mprocs session so they can share one terminal
# surface.
#
# Reinstall-without-quitting workflow:
#   When hacking on the handler/worktree projects themselves you often want to
#   `go install` (or equivalent) a fresh binary. The old binary has to be killed
#   first. Each mprocs pane therefore runs its command through a self-restarting
#   supervisor: when the child process exits for ANY reason (you kill it, it
#   crashes, it exits cleanly), the supervisor waits 5 seconds and relaunches it.
#   So you can kill the running `handler`/`worktree`, install the new binary, and
#   within 5s the pane comes back up on the new binary — no need to quit mprocs.
#   Quitting mprocs (or Ctrl-C) stops everything as usual.
#
# The supervisor is this same script re-invoked in a hidden `--supervise` mode,
# so there is only one file to maintain.

set -euo pipefail

RESTART_DELAY=5

usage() {
  cat <<'EOF'
Usage: cmux-tool-servers

Run `handler ui` and `worktree ui` in parallel panes in mprocs. Each pane
restarts its command 5 seconds after it exits, so you can kill a running
binary, install a new one, and have it come back automatically.

Requires: mprocs, handler, worktree (all on PATH). Best run inside cmux.
EOF
}

# Hidden supervise mode: `cmux-tool-servers --supervise <cmd> [args...]`
# Runs the command in a loop, restarting RESTART_DELAY seconds after each exit.
# NOTE: `set -e` must not apply here — the child exiting non-zero is expected.
if [ "${1:-}" = "--supervise" ]; then
  shift
  if [ "$#" -eq 0 ]; then
    echo "cmux-tool-servers: --supervise requires a command" >&2
    exit 2
  fi
  set +e
  while true; do
    "$@"
    status=$?
    echo ""
    echo "[cmux-tool-servers] '$*' exited (status $status). Restarting in ${RESTART_DELAY}s… (kill mprocs to stop)"
    sleep "$RESTART_DELAY"
  done
fi

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  "")
    ;;
  *)
    echo "cmux-tool-servers: unknown argument '$1'" >&2
    usage >&2
    exit 2
    ;;
esac

# Preflight: everything we need must be on PATH.
missing=""
for tool in mprocs handler worktree; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    missing="$missing $tool"
  fi
done
if [ -n "$missing" ]; then
  echo "cmux-tool-servers: required tool(s) not found on PATH:$missing" >&2
  exit 1
fi

# Resolve this script's own path so mprocs invokes the same file for --supervise,
# regardless of how it was called (symlink in bin/, direct path, etc.).
self="$0"
if command -v realpath >/dev/null 2>&1; then
  self="$(realpath "$0")"
fi

exec mprocs \
  --names "handler,worktree" \
  "$self --supervise handler ui" \
  "$self --supervise worktree ui"
