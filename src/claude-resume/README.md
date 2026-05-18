# claude-resume

Resume a Claude Code session from any directory. Looks up the session's working directory and resumes it there, so you don't need to `cd` first.

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (session data in `~/.claude/projects/`)

## Usage

```bash
claude-resume <session-id>                # resume a session
claude-resume <session-id> --model opus   # pass extra args to claude
```

Any extra arguments after the session ID are passed through to `claude`.

Find session IDs with [`claude-sessions`](claude-sessions.md).

## See also

- [`claude-sessions`](claude-sessions.md) — List all sessions across projects
