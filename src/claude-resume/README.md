# claude-resume

Resume a Claude Code session from any directory. Accepts a session ID or a search term to find a session by message content. Looks up the session's working directory and resumes it there, so you don't need to `cd` first.

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (session data in `~/.claude/projects/`)
- [`claude-sessions`](../claude-sessions/) (used for search)

## Usage

```bash
claude-resume <session-id>                # resume by ID
claude-resume "search text"              # find and resume by message content
claude-resume <session-id> --model opus   # pass extra args to claude
```

When given a search term instead of a session ID, the script searches for sessions containing the text and lets you pick one interactively (via `claude-sessions --pick`).

Any extra arguments after the session ID or search term are passed through to `claude`.

## See also

- [`claude-sessions`](../claude-sessions/) — List all sessions across projects
