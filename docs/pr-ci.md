# pr-ci

Check or watch CI status for a GitHub pull request. Shows a summary of passed, failed, and pending checks. In watch mode, polls until all checks complete and sends a macOS alert.

## Prerequisites

- [GitHub CLI](https://cli.github.com/) (`gh`, must be authenticated)

## Usage

```bash
pr-ci <pr>                 # one-shot status summary
pr-ci <pr> --watch [SEC]   # poll every SEC seconds (default 120), alert when done
```

`<pr>` can be a PR number, URL, or branch name — anything `gh pr checks` accepts.

### One-shot mode

```bash
$ pr-ci 6999
PR 6999 — CI Status
─────────────────────────────────
Passed: 36  Failed: 1  Pending: 3  Skipped: 0

Failed checks:
  ✗ Cypress-Mock-Tests (distributedWorkloads, ...)

Pending checks:
  ⏳ Cypress-Mock-Tests (projects/tabs, ...)
  ⏳ Red Hat Konflux
  ⏳ tide
```

### Watch mode

Polls at a regular interval and shows a macOS alert when all checks are done.

```bash
pr-ci 6999 --watch         # poll every 2 minutes
pr-ci 6999 --watch 60      # poll every 60 seconds
pr-ci 6999 -w 30           # short flag
```

Output while watching:

```
Watching every 120s… (Ctrl-C to stop)

[14:32:15] Pending: 3  Passed: 36  Failed: 0
[14:34:16] Pending: 1  Passed: 38  Failed: 0
[14:36:17] All checks complete!

Passed: 39  Failed: 1  Pending: 0  Skipped: 2

Failed checks:
  ✗ Cypress-Mock-Tests (distributedWorkloads, ...)
```

When checks complete, a macOS alert pops up with the pass/fail summary.

## Options

| Flag | Description |
|------|-------------|
| `--watch`, `-w` | Enable watch mode (poll until done) |
| `[SECONDS]` | Poll interval in seconds (default 120, follows `--watch`) |
| `--help`, `-h` | Show usage |

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success (all checks reported) |
| 1 | Usage error or `gh` not available |
