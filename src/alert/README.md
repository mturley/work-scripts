# alert

Show a macOS alert dialog. Handy for getting your attention when a long-running command finishes — optionally with a peek at its output.

```bash
some-command && alert "it's done"
npm test; alert -t "tests" "finished with status $?"
npm run build 2>&1 | alert -t "build" "done"   # includes head/tail of the output
```

## Options

| Flag | Description |
|------|-------------|
| `-t <title>` | Alert title (default: `Alert`) |
| `-n <lines>` | Lines to show from each end of piped input (default: `5`) |
| `-h`, `--help` | Show usage |

All remaining arguments are joined with spaces to form the message body.

## Piped input

If stdin is a pipe, its contents are appended to the message body:

- Up to `2 × n` lines are shown in full
- Longer input shows the first `n` and last `n` lines, with `[... N more lines ...]` between them
- Empty input is ignored

```
$ seq 30 | alert -t "long" "done"

  done

  1
  2
  3
  4
  5
  [... 20 more lines ...]
  26
  27
  28
  29
  30
```

A message argument is optional when input is piped.

## Behavior

1. Runs `osascript` with AppleScript's `display alert` — not `display notification`, which is unreliable on macOS and can be silently suppressed
2. Shows a modal dialog with a single `OK` button
3. Blocks until the alert is dismissed, then exits `0`

Title and message are passed to AppleScript as `argv`, so quotes and apostrophes in them need no escaping.

## Setup

Requires macOS. No additional configuration needed.
