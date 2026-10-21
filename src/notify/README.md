# notify

Send a formatted Telegram notification via [telert](https://github.com/navig-me/telert). Built for AI agent sessions that need to reach you on your phone, but works from any shell.

```bash
notify -k done -t "Phase 1 done" "All 42 tests pass. Ready for review."
notify -k input -l https://redhat.atlassian.net/browse/RHOAIENG-12345 "Reuse the cursor table, or add a new one?"
notify -k paused "Rate-limited. Wake job scheduled for 3:11pm."
```

The first example arrives as:

> ✅ **Phase 1 done**
>
> All 42 tests pass. Ready for review.
>
> 📂 `worktree` · 🌿 `tasks` · 💬 my-session

## Options

| Flag | Description |
|------|-------------|
| `-k`, `--kind <kind>` | Message kind, which sets the emoji and default title (default: `info`) |
| `-t`, `--title <title>` | Bold headline (default: the kind's label) |
| `-l`, `--link <url>` | Link to include on its own line; repeatable |
| `-s`, `--session <name>` | Session name (default: output of `handler session-name`) |
| `-n`, `--dry-run` | Print the HTML message instead of sending it |
| `-h`, `--help` | Show usage |

All remaining arguments are joined with spaces to form the message body. The body is optional.

### Kinds

| Kind | Emoji | Default title |
|------|-------|---------------|
| `done` | ✅ | Done |
| `input` | ❓ | Needs your input |
| `failed` | ❌ | Failed |
| `paused` | ⏸️ | Paused |
| `resumed` | ▶️ | Resumed |
| `info` | ℹ️ | FYI |

## Context footer

After the body, a footer line shows whatever context is available:

- **📂 worktree**: basename of `git rev-parse --show-toplevel`
- **🌿 branch**: `git branch --show-current`, or the short SHA when detached
- **💬 session**: the agent-handler session name, cut to 24 characters

Missing pieces are skipped, so outside a git repo or without `handler` you just get less footer.

Each `-l` link goes on its own `🔗` line with a short label:

| URL | Label |
|-----|-------|
| `https://github.com/<org>/<repo>/pull/123` | `PR #123` |
| `https://github.com/<org>/<repo>/issues/45` | `Issue #45` |
| `https://<site>.atlassian.net/browse/RHOAIENG-12345` | `RHOAIENG-12345` |
| anything else | the hostname |

## Why not `telert send`?

When stdin isn't a TTY, which is always the case under an AI agent's shell, the telert CLI switches to pipeline mode. It treats `send` as the message and your text as an exit status, and delivers `send (exit <your text>)`. `notify` calls telert's Python API (`telert.api.send`) directly, which has no such check, and sends with Telegram's HTML parse mode. All text and URLs are HTML-escaped, since a stray `<` would otherwise make Telegram reject the message.

## Setup

Requires Python 3 and telert, installed and configured with a Telegram provider:

```bash
pipx install telert
telert config telegram --token <bot-token> --chat-id <chat-id> --set-default
```

telert usually lives in its own pipx virtualenv, so `notify` starts with the system `python3` and, if `telert` isn't importable there, re-runs itself under the interpreter named in telert's entry point script.
