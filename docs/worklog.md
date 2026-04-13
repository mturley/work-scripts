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
- `worklog undo` — remove the last entry from the activity log (handles combined entries correctly)
- `worklog combine` — consolidate entries that share the same reference (see below)
- `worklog test` — insert sample entries into today's daily note to preview formatting
- `worklog help` — show full usage

## Combining duplicate entries

`worklog combine` scans today's activity log for entries with the same main reference (e.g. two entries for `RHOAIENG-12345`) and consolidates them. The combined entry:

- Stacks all timestamp/emoji lines from the duplicates
- Keeps the reference line and title from the first occurrence
- Merges bullet lists from all entries (deduplicating exact matches)
- Stays in the position of the first occurrence

```markdown
1:19 PM — 📋 👀 Seen Jira Bug
1:31 PM — 📋 ✏️ Updated Jira Bug

[RHOAIENG-57824](url) (Critical, mine)
*Model Catalog Settings page returns 500*

- Notes: Seen as part of fixing the renamed ConfigMap constant
- PR: [model-registry#2593](url) (by @mturley): *Rename default catalog sources ConfigMap*
- Notes: Linked model-registry#2593 to Git Pull Request field
```

Running `worklog combine` when there are no duplicates is a no-op.

## Slack URL linkification

Bare Slack URLs in free-text inputs (freeform entries, `--detail` values, and interactive notes) are automatically converted to `[See slack thread](url)` markdown links.

## Log entry format

Each entry is a block of plain markdown appended to the daily note, separated by blank lines. Entries are identified by the timestamp line pattern (`H:MM AM/PM — <emoji>`).

```markdown
3:15 PM — 🔀 📝 Reviewed PR

[odh-dashboard#6300](url) (by @author)
*Fix pagination*

- Review: "Looks good overall..."
- Jira: [RHOAIENG-12345](url) — *Fix pagination* (Major, mine)


4:00 PM — 📋 👀 Seen Jira Bug

[RHOAIENG-12345](url) (Major, mine)
*Fix pagination*

- Epic: [RHOAIENG-12000](url) — *Model Registry improvements*
- PR: [odh-dashboard#6300](url) (by @author): *Fix pagination*
```

## Setup

1. Enable the Obsidian CLI: Obsidian → Settings → General → Advanced
2. Create a `.env` file in the work-scripts directory:
   ```bash
   cp .env.example .env
   # Fill in OBSIDIAN_VAULT, JIRA_HOST, JIRA_EMAIL, and JIRA_API_TOKEN
   # Generate a Jira token at: https://id.atlassian.com/manage-profile/security/api-tokens
   ```
