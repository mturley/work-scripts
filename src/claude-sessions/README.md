# claude-sessions

List all Claude Code sessions across all projects, most recent first. Shows session ID, working directory, first user message ("name"), and last user message. Pages 5 sessions at a time with an interactive prompt, or search for sessions containing specific text.

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (session data in `~/.claude/projects/`)
- Python 3

## Usage

```bash
claude-sessions                 # list sessions, 5 at a time
claude-sessions "text"          # search for sessions containing text
claude-sessions --pick "text"   # interactive picker (for claude-resume)
```

**Without arguments:** Pages 5 sessions at a time. Press Enter at the `[Enter for more]` prompt to load the next page, or Ctrl-C to stop.

**With a search term:** Searches through all sessions (most recent first) for messages containing the given text (case-insensitive). Shows a spinner while searching. When a match is found, displays the session and prompts "Enter to keep looking". Press Enter to continue searching or Ctrl-C to stop.

**With `--pick`:** Like search mode, but prompts `[r]esume this session / [k]eep looking / [a]bort?` for each match. On resume, outputs the session ID to stdout and exits. Designed for use by other scripts (e.g. `claude-resume`).

## Output

```
f5e4d769-...  ~/git/my-project
  ┌─ Prompt (2026-05-15 14:10):  Review the authentication module
  └─ Latest (2026-05-18 12:58):  Can you also check the tests?

2d1cb6b6-...  ~/git/other-project
  ┌─ Prompt (2026-05-18 11:30):  Add dark mode support
  └─ Latest (2026-05-18 11:55):  Commit and push
```

- **First line**: session ID, working directory
- **┌─**: First real user message (the session "name") with timestamp
- **└─**: Most recent user message with timestamp

## See also

- [`claude-resume`](claude-resume.md) — Resume a session from any directory
