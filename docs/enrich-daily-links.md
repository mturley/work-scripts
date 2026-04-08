# enrich-daily-links

Enrich GitHub PR, Jira, and Slack URLs in today's [Obsidian daily note](https://obsidian.md/help/plugins/daily-notes) with short, descriptive markdown links. Jira links are enriched with the issue type and title via the Jira API.

```bash
enrich-daily-links            # enrich links in today's note
enrich-daily-links --dry-run  # preview changes without modifying the file
enrich-daily-links --help     # show usage
```

## What it does

Scans today's daily note for GitHub PR URLs, Jira issue URLs, and Slack thread links, and formats them as descriptive markdown links. Jira links include the issue type and title fetched from the Jira API. Slack links are labeled "Slack thread".

### Bare URLs

```
https://github.com/opendatahub-io/odh-dashboard/pull/6300
  -> [odh-dashboard#6300](https://github.com/opendatahub-io/odh-dashboard/pull/6300)

https://your-org.atlassian.net/browse/PROJ-12345
  -> [PROJ-12345 (Bug): Fix the pagination issue](https://your-org.atlassian.net/browse/PROJ-12345)

https://myteam.slack.com/archives/C012345/p1234567890
  -> [Slack thread](https://myteam.slack.com/archives/C012345/p1234567890)
```

### Markdown links with URL as link text

```
[https://github.com/org/repo/pull/123](https://github.com/org/repo/pull/123)
  -> [repo#123](https://github.com/org/repo/pull/123)

[https://your-org.atlassian.net/browse/KEY-123](https://your-org.atlassian.net/browse/KEY-123)
  -> [KEY-123 (Story): Add new feature](https://your-org.atlassian.net/browse/KEY-123)
```

### HTML links with URL as link text

```
<a href="https://your-org.atlassian.net/browse/KEY-123">https://your-org.atlassian.net/browse/KEY-123</a>
  -> [KEY-123 (Story): Add new feature](https://your-org.atlassian.net/browse/KEY-123)
```

### Jira links with just the key as link text

Existing markdown links where the link text is only the Jira issue key are enriched with type and title:

```
[KEY-123](https://your-org.atlassian.net/browse/KEY-123)
  -> [KEY-123 (Story): Add new feature](https://your-org.atlassian.net/browse/KEY-123)
```

### Already-enriched links

Links that already have descriptive (non-URL, non-bare-key) link text are left unchanged:

```
[KEY-123 (Bug): Fix the thing](url)                       ->  no change
[odh-dashboard#6300](https://github.com/.../pull/6300)     ->  no change
[My custom text](https://example.com)                      ->  no change
[Slack thread](https://myteam.slack.com/archives/...)      ->  no change
```

## Recognized URL patterns

- **GitHub PRs:** `https://github.com/<owner>/<repo>/pull/<number>` -> `<repo>#<number>`
- **Jira issues:** `https://<any-host>/browse/<KEY-123>` -> `<KEY-123> (<Type>): <Title>`
- **Slack threads:** `https://<any>.slack.com/...` -> `Slack thread`

## Setup

1. Enable the Obsidian CLI: Obsidian -> Settings -> General -> Advanced
2. Set `OBSIDIAN_VAULT` in your `.env` file (see [worklog setup](worklog.md#setup))
3. For Jira enrichment, also set `JIRA_HOST`, `JIRA_EMAIL`, and `JIRA_API_TOKEN` in `.env` (without credentials, Jira links are formatted with just the issue key)
