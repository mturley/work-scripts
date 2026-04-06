# worklog

Append timestamped, metadata-enriched activity entries to today's [Obsidian daily note](https://obsidian.md/help/plugins/daily-notes). Designed as a quick way to record what you've been doing throughout the day for scrum updates and personal reference.

Also available as `wlog` (symlink).

```bash
worklog                                    # free-form log entry (prompts for text)
worklog help                               # show full usage
worklog pr opened https://github.com/org/repo/pull/123
worklog pr reviewed org/repo#123
worklog pr approved #123                   # infers repo from current directory
worklog jira seen RHOAIENG-12345
worklog jira commented https://issues.redhat.com/browse/RHOAIENG-12345
```

## PR commands

`worklog pr <action> <ref>`

Actions: `opened`, `seen`, `reviewed`, `commented`, `approved`

- Fetches PR title, author, and URL via `gh`
- For `reviewed`/`commented`, includes a truncated excerpt of your latest review or comment
- Searches Jira for linked issues (current sprint) and includes them as sub-bullets

Reference formats: full GitHub URL, `owner/repo#123`, `repo#123`, `#123`, or bare `123` (the last two infer the repo from the current directory).

## Jira commands

`worklog jira <action> <ref>`

Actions: `opened`, `seen`, `updated`, `commented`

- Fetches issue type, summary, assignee, priority, and epic parent
- For `commented`, includes a truncated excerpt of the latest comment
- Includes linked PRs from the "Git Pull Request" custom field

Reference formats: issue key (`RHOAIENG-12345`) or full URL (`https://issues.redhat.com/browse/RHOAIENG-12345` or `https://redhat.atlassian.net/browse/RHOAIENG-12345`).

## Log entry format

Each entry is a markdown bullet appended to the daily note. The main line is bold for readability. Sub-bullets include linked issues/PRs, review excerpts, and optional user notes.

```markdown
- **3:15 PM — 🔀 📝 Reviewed PR [odh-dashboard#6300](url) (by @author)**
				*Fix pagination*
	- Review: "Looks good overall, one minor nit on the error handling..."
	- Linked: [RHOAIENG-12345](url) — *Fix pagination*
	  (Major, Assigned to Mike Turley)
	- Notes: discussed approach in standup

- **4:00 PM — 📋 👀 Seen [RHOAIENG-12345](url) (Bug, Major) — assigned to Mike Turley**
				*Fix pagination*
	- Epic: [RHOAIENG-12000](url) — *Model Registry improvements*
	- PR: [odh-dashboard#6300](url) (by @author): *Fix pagination*
```

## Setup

1. Enable the Obsidian CLI: Obsidian → Settings → General → Advanced
2. For Jira integration, create a `.env` file in the work-scripts directory:
   ```bash
   cp .env.example .env
   # Fill in JIRA_HOST, JIRA_EMAIL and JIRA_API_TOKEN
   # Generate a token at: https://id.atlassian.com/manage-profile/security/api-tokens
   ```
