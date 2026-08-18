# claude-fork

Fork a Claude Code session into a new, independent session. Resumes the given session with `--fork-session` so the original session is left untouched, and names the fork automatically.

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)

## Usage

```bash
claude-fork <session-id-or-name>                 # fork, named "<session>-fork"
claude-fork <session-id-or-name> --name my-fork  # fork with a custom name
claude-fork <session-id-or-name> --model opus     # pass extra args to claude
```

The first argument is the session id or name to fork. By default the new session is named `<session>-fork`. Pass `--name <name>` to override that with your own name.

Any other arguments are passed through to `claude`.

Runs:

```bash
claude --resume <session> --fork-session --name <name> [claude args...]
```

## See also

- [`claude-resume`](../claude-resume/) — Resume a Claude Code session from any directory
- [`claude-sessions`](../claude-sessions/) — List all sessions across projects
