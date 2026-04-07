# pr-ci

Check or watch CI status for a GitHub pull request. Shows the PR title and a summary of passed, failed, and pending checks. By default, watches (polls) until all checks complete and sends a macOS alert. The `tide` check (which requires PR approval) is ignored when it's the only pending check.

## Prerequisites

- [GitHub CLI](https://cli.github.com/) (`gh`, must be authenticated)

## Usage

```bash
pr-ci <pr>           # watch CI, polling every 120s, alert when done
pr-ci <pr> 60        # watch CI, polling every 60s
pr-ci <pr> --once    # show current status once and exit
```

`<pr>` can be a PR number, URL, or branch name — anything `gh pr checks` accepts.

### Watch mode (default)

Polls at a regular interval and shows a macOS alert when all checks are done.

```bash
pr-ci 6999           # poll every 2 minutes
pr-ci 6999 60        # poll every 60 seconds
```

Output while watching:

```
PR #6999: Fix the widget layout

CI Status
─────────────────────────────────
Passed: 36  Failed: 0  Pending: 3  Skipped: 0

Pending checks:
  ⏳ Cypress-Mock-Tests (projects/tabs, ...)
  ⏳ Red Hat Konflux
  ⏳ tide

Watching every 120s… (Ctrl-C to stop)

[14:32:15] Pending: 3  Passed: 36  Failed: 0
[14:34:16] Pending: 1  Passed: 38  Failed: 0
[14:36:17] All checks complete!

Passed: 39  Failed: 0  Pending: 1  Skipped: 2

Pending: tide (requires approval — ignored)
```

When checks complete, a macOS alert pops up with the pass/fail summary.

### One-shot mode

```bash
$ pr-ci 6999 --once
PR #6999: Fix the widget layout

CI Status
─────────────────────────────────
Passed: 36  Failed: 1  Pending: 3  Skipped: 0

Failed checks:
  ✗ Cypress-Mock-Tests (distributedWorkloads, ...)

Pending checks:
  ⏳ Cypress-Mock-Tests (projects/tabs, ...)
  ⏳ Red Hat Konflux
  ⏳ tide
```

### iTerm session title

When running inside [iTerm2](https://iterm2.com/), `pr-ci` sets the session (tab/window) title to `pr-ci #<number>` so you can identify which PR a tab is watching. The title is refreshed each poll cycle in watch mode.

## Options

| Flag | Description |
|------|-------------|
| `[SECONDS]` | Poll interval in seconds (default 120) |
| `--once` | Show status once and exit (no watching) |
| `--help`, `-h` | Show usage |

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success (all checks reported) |
| 1 | Usage error or `gh` not available |
