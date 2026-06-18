#!/usr/bin/env bash
# cmux-perf-monitor - Sample cmux process metrics at regular intervals.
# Usage: cmux-perf-monitor [--interval SECONDS] [--output FILE]

set -euo pipefail

INTERVAL=180
OUTPUT="/tmp/cmux-monitor.csv"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --interval) INTERVAL="$2"; shift 2 ;;
    --output)   OUTPUT="$2"; shift 2 ;;
    --reset)    RESET=1; shift ;;
    -h|--help)
      echo "Usage: cmux-perf-monitor [--interval SECONDS] [--output FILE] [--reset]"
      echo ""
      echo "Samples cmux process metrics at regular intervals and appends to a CSV."
      echo ""
      echo "Options:"
      echo "  --interval SECONDS  Sampling interval (default: 180)"
      echo "  --output FILE       Output CSV path (default: /tmp/cmux-monitor.csv)"
      echo "  --reset             Clear existing data and start fresh"
      echo "  -h, --help          Show this help"
      echo ""
      echo "Columns: timestamp, cmux_cpu, cmux_mem_pct, cmux_rss_mb,"
      echo "         claude_sessions, cmux_surfaces, child_procs, open_fds"
      echo ""
      echo "Press Ctrl-C to stop."
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

find_cmux_pid() {
  ps aux | grep '[c]mux.app/Contents/MacOS/cmux' | awk '{print $2}' | head -1
}

pid=$(find_cmux_pid)
if [[ -z "$pid" ]]; then
  echo "Error: cmux process not found." >&2
  exit 1
fi

if [[ "${RESET:-}" == "1" ]] || [[ ! -f "$OUTPUT" ]] || ! head -1 "$OUTPUT" 2>/dev/null | grep -q "^timestamp,"; then
  echo "timestamp,cmux_cpu,cmux_mem_pct,cmux_rss_mb,claude_sessions,cmux_surfaces,child_procs,open_fds" > "$OUTPUT"
fi

echo "Monitoring cmux (PID $pid) every ${INTERVAL}s → $OUTPUT"
echo "Press Ctrl-C to stop."

while true; do
  pid=$(find_cmux_pid)
  if [[ -z "$pid" ]]; then
    echo "$(date '+%H:%M:%S') cmux process gone, waiting..." >&2
    sleep "$INTERVAL"
    continue
  fi

  cmux_cpu=$(ps -p "$pid" -o pcpu | tail -1 | xargs)
  cmux_mem=$(ps -p "$pid" -o pmem | tail -1 | xargs)
  cmux_rss_kb=$(ps -p "$pid" -o rss | tail -1 | xargs)
  cmux_rss_mb=$((cmux_rss_kb / 1024))
  claude_sessions=$(pgrep -f '.local/bin/claude' | wc -l | xargs)
  cmux_surfaces=$(ps aux | grep 'cmux-surface-resume' | grep -v grep | wc -l | xargs)
  child_procs=$(pgrep -P "$pid" | wc -l | xargs)
  open_fds=$(lsof -p "$pid" 2>/dev/null | wc -l | xargs)

  line="$(date '+%H:%M:%S'),$cmux_cpu,$cmux_mem,$cmux_rss_mb,$claude_sessions,$cmux_surfaces,$child_procs,$open_fds"
  echo "$line" >> "$OUTPUT"
  echo "$line"

  sleep "$INTERVAL"
done
