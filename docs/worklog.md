# worklog

Append timestamped, metadata-enriched activity entries to today's [Obsidian daily note](https://obsidian.md/help/plugins/daily-notes). Designed as a quick way to record what you've been doing throughout the day for scrum updates and personal reference.

Also available as `wlog` (symlink).

```bash
worklog                                    # free-form log entry (prompts for text)
worklog help                               # show full usage
worklog pr opened https://github.com/org/repo/pull/123
worklog pr reviewed org/repo#123
worklog pr approved #123                   # infers repo from current directory
worklog jira started RHOAIENG-12345
worklog jira seen RHOAIENG-12345
worklog jira commented https://issues.redhat.com/browse/RHOAIENG-12345
```

## PR commands

`worklog pr <action> <ref>`

Actions: `opened`, `closed`, `seen`, `reviewed`, `commented`, `approved`, `updated`

- Fetches PR title, author, and URL via `gh`
- For `reviewed`/`commented`, includes a truncated excerpt of your latest review or comment
- Searches Jira for linked issues (current sprint) and includes them as sub-details

Reference formats: full GitHub URL, `owner/repo#123`, `repo#123`, `#123`, or bare `123` (the last two infer the repo from the current directory).

## Jira commands

`worklog jira <action> <ref>`

Actions: `opened`, `started`, `closed`, `seen`, `updated`, `commented`

- Fetches issue type, summary, assignee, priority, and epic parent
- For `commented`, includes a truncated excerpt of the latest comment
- Includes linked PRs from the "Git Pull Request" custom field

Reference formats: issue key (`RHOAIENG-12345`) or full URL (`https://issues.redhat.com/browse/RHOAIENG-12345` or `https://redhat.atlassian.net/browse/RHOAIENG-12345`).

## Other commands

- `worklog open` — open today's daily note in Obsidian
- `worklog undo` — remove the last row from the activity table
- `worklog test` — insert sample entries into today's daily note to preview formatting
- `worklog help` — show full usage

## Slack URL linkification

Bare Slack URLs in free-text inputs (freeform entries, `--detail` values, and interactive notes) are automatically converted to `[See slack thread](url)` markdown links.

## Log entry format

Each entry is a row in a 2-column markdown table appended to the daily note (or created if missing). The table auto-repairs extra empty columns that Obsidian's editor may add accidentally.

```markdown
| Time | |
|---|---|
| 3:15 PM | 🔀 📝 Reviewed PR<br><br>[odh-dashboard#6300](url) (by @author)<br>*Fix pagination*<ul><li>Review: "Looks good overall..."</li><li>Jira: [RHOAIENG-12345](url) — *Fix pagination* (Major, mine)</li></ul> |
| 4:00 PM | 📋 👀 Seen Jira Bug<br><br>[RHOAIENG-12345](url) (Major, mine)<br>*Fix pagination*<ul><li>Epic: [RHOAIENG-12000](url) — *Model Registry improvements*</li><li>PR: [odh-dashboard#6300](url) (by @author): *Fix pagination*</li></ul> |
```

## Setup

1. Enable the Obsidian CLI: Obsidian → Settings → General → Advanced
2. Create a `.env` file in the work-scripts directory:
   ```bash
   cp .env.example .env
   # Fill in OBSIDIAN_VAULT, JIRA_HOST, JIRA_EMAIL, and JIRA_API_TOKEN
   # Generate a Jira token at: https://id.atlassian.com/manage-profile/security/api-tokens
   ```
