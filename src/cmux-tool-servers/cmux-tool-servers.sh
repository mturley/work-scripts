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
#
# --bind:
#   `--bind ADDR` is passed straight through to `worktree ui` so its web UI can
#   be reached from other devices (e.g. a phone on the same LAN). That UI has no
#   authentication, so `worktree ui` warns and asks for confirmation before
#   binding a non-loopback address. mprocs gives each pane a pty, so by default
#   it prompts in the pane and a human answers every bind. `--yes` is forwarded
#   only when passed explicitly here — the supervisor re-asks on every restart,
#   which gets tiresome once you have decided. The warning is still printed
#   either way; --yes only skips the prompt. `handler ui` is not affected.

set -euo pipefail

RESTART_DELAY=5

usage() {
  cat <<'EOF'
Usage: cmux-tool-servers [--bind ADDR] [--yes]

Run `handler ui` and `worktree ui` in parallel panes in mprocs. Each pane
restarts its command 5 seconds after it exits, so you can kill a running
binary, install a new one, and have it come back automatically.

Options:
  --bind ADDR  Host/IP for `worktree ui` to bind (e.g. 0.0.0.0 to reach the
               worktree UI from other devices on your LAN). Defaults to
               127.0.0.1, i.e. this machine only. `worktree ui` warns and asks
               for confirmation in its pane before binding a non-loopback
               address, including after each supervisor restart.
               NOTE: this applies to `worktree ui` only. `handler ui` is not
               affected and stays bound to loopback.
  --yes        Forwarded to `worktree ui` to skip that confirmation prompt.
               The warning is still printed. Useful because the supervisor
               restarts the pane, and each restart otherwise re-asks.

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

bind_addr=""
assume_yes=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --bind)
      if [ "$#" -lt 2 ]; then
        echo "cmux-tool-servers: --bind requires an address" >&2
        exit 2
      fi
      bind_addr="$2"
      shift 2
      ;;
    --yes)
      assume_yes=1
      shift
      ;;
    --bind=*)
      bind_addr="${1#--bind=}"
      if [ -z "$bind_addr" ]; then
        echo "cmux-tool-servers: --bind requires an address" >&2
        exit 2
      fi
      shift
      ;;
    *)
      echo "cmux-tool-servers: unknown argument '$1'" >&2
      usage >&2
      exit 2
      ;;
  esac
done

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

# Build the worktree pane's command. `worktree ui` owns the warning and the
# confirmation prompt — the mprocs pane is a pty, so it can ask there. --yes is
# forwarded only when the caller asked for it, never added on our own.
worktree_cmd="$self --supervise worktree ui --no-open"
if [ -n "$bind_addr" ]; then
  worktree_cmd="$worktree_cmd --bind $bind_addr"
fi
if [ "$assume_yes" = "1" ]; then
  worktree_cmd="$worktree_cmd --yes"
fi

exec mprocs \
  --names "handler,worktree" \
  "$self --supervise handler ui --no-open" \
  "$worktree_cmd"
