# cmux-perf-monitor

Samples cmux process metrics at regular intervals to diagnose performance degradation.

## Background

cmux (the terminal multiplexer app) has exhibited a pattern where pane/tab switching becomes progressively laggy over time. In one observed case (June 2026), after ~15 days of uptime, cmux consumed 300% CPU and 4.7 GB RAM. The degradation timeline is unclear — it may take hours or days to manifest.

This script was created to capture a time-series of cmux resource usage so that when lag recurs, we have data showing what grew (CPU, memory, file descriptors, child processes) and what correlated with the growth (number of Claude Code sessions, managed surfaces).

## Usage

```bash
# Default: sample every 3 minutes, write to /tmp/cmux-monitor.csv
cmux-perf-monitor

# Custom interval and output
cmux-perf-monitor --interval 60 --output ~/cmux-data.csv

# Run in background
cmux-perf-monitor &
```

## CSV Columns

| Column | Description |
|--------|-------------|
| `timestamp` | `HH:MM:SS` sample time |
| `cmux_cpu` | cmux CPU % at sample time (point-in-time, can spike) |
| `cmux_mem_pct` | cmux memory as % of total RAM |
| `cmux_rss_mb` | cmux resident set size in MB |
| `claude_sessions` | count of running `claude` CLI processes |
| `cmux_surfaces` | count of cmux-managed terminal panes |
| `child_procs` | direct child processes of cmux |
| `open_fds` | open file descriptors (leak indicator) |

## What to look for

- **Memory (rss_mb) trending upward over hours/days** → memory leak
- **FDs (open_fds) growing steadily** → file descriptor leak
- **CPU baseline creeping up** → runaway rendering or event loop
- **Correlation with claude_sessions or surfaces** → hook traffic or surface management overhead

## Analysis tips

Hourly averages (paste into a Claude session):
```bash
cat /tmp/cmux-monitor.csv
# ask Claude to summarize trends by hour
```

Or quick check for growth:
```bash
head -5 /tmp/cmux-monitor.csv  # baseline
tail -5 /tmp/cmux-monitor.csv  # current
```
