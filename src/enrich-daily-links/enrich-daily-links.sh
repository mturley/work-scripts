#!/usr/bin/env bash
# enrich-daily-links - Enrich links in today's Obsidian daily note.
# Replaces bare GitHub PR, Jira, and Slack URLs (and links using the URL as
# link text) with short formatted markdown links. Jira links are enriched with
# issue type and title via the Jira API. Slack links are labeled "Slack thread".
# Usage: enrich-daily-links [--dry-run]

set -euo pipefail

WORK_SCRIPTS_DIR="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------

usage() {
  cat <<EOF
Usage: enrich-daily-links [--dry-run]

Format bare GitHub PR and Jira URLs in today's Obsidian daily note into
short markdown links.

Transformations:
  Bare URLs:
    https://github.com/org/repo/pull/123      ->  [repo#123](url)
    https://your-org.atlassian.net/browse/KEY  ->  [KEY (Type): Title](url)
    https://team.slack.com/archives/...        ->  [Slack thread](url)

  Links with URL as link text:
    [https://...](https://...)                 ->  [short](url)
    <a href="url">url</a>                     ->  [short](url)

  Jira links with just the key as link text:
    [KEY-123](url)                             ->  [KEY-123 (Type): Title](url)

  Already-formatted links are left unchanged:
    [repo#123](url)                            ->  no change
    [KEY-123 (Bug): Title](url)                ->  no change
    [Slack thread](url)                        ->  no change

Jira enrichment requires JIRA_HOST, JIRA_EMAIL, and JIRA_API_TOKEN in .env.
Without credentials, Jira links are formatted with just the issue key.

Options:
  --dry-run    Show what would change without modifying the file
  --help       Show this help
EOF
  exit 0
}

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

DRY_RUN=false

case "${1:-}" in
  -h|--help|help) usage ;;
  --dry-run) DRY_RUN=true ;;
esac

if ! command -v obsidian >/dev/null 2>&1; then
  echo "ERROR: Obsidian CLI not found on PATH." >&2
  echo "Enable it in Obsidian: Settings -> General -> Advanced." >&2
  exit 1
fi

# Load .env
OBSIDIAN_VAULT=""
JIRA_HOST=""
JIRA_EMAIL=""
JIRA_API_TOKEN=""
env_file="$WORK_SCRIPTS_DIR/.env"
if [ -f "$env_file" ]; then
  while IFS='=' read -r key value; do
    case "$key" in \#*|"") continue ;; esac
    key="$(echo "$key" | tr -d '[:space:]')"
    value="$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    case "$key" in
      OBSIDIAN_VAULT) OBSIDIAN_VAULT="$value" ;;
      JIRA_HOST) JIRA_HOST="$value" ;;
      JIRA_EMAIL) JIRA_EMAIL="$value" ;;
      JIRA_API_TOKEN) JIRA_API_TOKEN="$value" ;;
    esac
  done < "$env_file"
fi

if [ -z "$OBSIDIAN_VAULT" ]; then
  echo "ERROR: OBSIDIAN_VAULT not set in .env" >&2
  exit 1
fi

# Get daily note path
today_relative="$(obsidian daily:path 2>/dev/null | tail -1)"
if [ -z "$today_relative" ]; then
  echo "ERROR: Could not get daily note path from Obsidian CLI" >&2
  exit 1
fi
daily_note="$OBSIDIAN_VAULT/$today_relative"

if [ ! -f "$daily_note" ]; then
  echo "ERROR: Daily note not found at: $daily_note" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Process links with Python
# ---------------------------------------------------------------------------

python3 -c "
import re
import sys
import json
import os

filepath = sys.argv[1]
dry_run = sys.argv[2] == 'true'
jira_host = sys.argv[3]
jira_email = sys.argv[4]
jira_token = sys.argv[5]

with open(filepath, 'r') as f:
    content = f.read()

original = content

# --- Jira API lookup ---

jira_cache = {}  # key -> (issue_type, summary) or None

def lookup_jira(key):
    if key in jira_cache:
        return jira_cache[key]
    if not jira_host or not jira_email or not jira_token:
        jira_cache[key] = None
        return None
    try:
        import subprocess
        url = f'https://{jira_host}/rest/api/2/issue/{key}?fields=summary,issuetype'
        result = subprocess.run(
            ['curl', '-s', '-u', f'{jira_email}:{jira_token}',
             '-H', 'Content-Type: application/json', url],
            capture_output=True, text=True, timeout=10)
        if result.returncode != 0:
            raise RuntimeError(f'curl failed: {result.stderr}')
        data = json.loads(result.stdout)
        fields = data.get('fields', {})
        issue_type = (fields.get('issuetype') or {}).get('name', '')
        summary = fields.get('summary', '')
        info = (issue_type, summary)
        jira_cache[key] = info
        return info
    except Exception as e:
        print(f'  (warning: could not fetch {key}: {e})', file=sys.stderr)
        jira_cache[key] = None
        return None

# --- URL shortening helpers ---

TITLE_MAX_LEN = 60

def truncate(text, max_len=TITLE_MAX_LEN):
    if len(text) <= max_len:
        return text
    return text[:max_len].rstrip() + '...'

def should_skip_enrichment(text, pos):
    \"\"\"Return True if a Jira link at this position should NOT be enriched
    because it's on the reference line of an activity log entry.

    Activity log entries look like:
      10:30 AM — 📋 🚀 Started Jira Bug
                                              <- blank line
      [RHOAIENG-12345](url) (Major, mine)     <- reference line (skip here)
      *Fix model registry pagination*         <- title line
                                              <- blank line
      - Epic: [RHOAIENG-48000](url) — *...*   <- detail lines (enrich here)
      - Notes: ...

    The reference line already has the Jira key, and the title is shown on
    the next line, so enriching it is redundant. Links in detail lines
    (starting with '- ') should still be enriched.
    \"\"\"
    # Find the current line
    line_start = text.rfind('\n', 0, pos) + 1
    line_end = text.find('\n', pos)
    if line_end == -1:
        line_end = len(text)

    # Detail lines (bullet points) should always be enriched
    line = text[line_start:line_end]
    if line.lstrip().startswith('- '):
        return False

    # Check if the line two above (skipping the blank line) is a timestamp line.
    # That means we're on the reference line of an activity log entry.
    # Walk back: current line start -> previous line (blank) -> line before that
    prev_line_end = line_start - 1  # points to the \n before current line
    if prev_line_end < 0:
        return False
    prev_line_start = text.rfind('\n', 0, prev_line_end) + 1
    prev_line = text[prev_line_start:prev_line_end]

    # The previous line should be blank (empty or whitespace only)
    if prev_line.strip() != '':
        return False

    # The line before the blank line should be a timestamp line
    ts_line_end = prev_line_start - 1
    if ts_line_end < 0:
        return False
    ts_line_start = text.rfind('\n', 0, ts_line_end) + 1
    ts_line = text[ts_line_start:ts_line_end]

    # Timestamp lines match: TIME — EMOJI ACTION (e.g. '10:30 AM — 📋 🚀 Started Jira Bug')
    if re.match(r'^\d{1,2}:\d{2}\s*[AP]M\s*\u2014\s*', ts_line):
        return True

    return False

def escape_md_link_text(text):
    \"\"\"Escape characters that break markdown link syntax in link text.\"\"\"
    for ch in ['[', ']', '(', ')']:
        text = text.replace(ch, '\\\\' + ch)
    return text

def format_jira_label(key, issue_type, summary):
    \"\"\"Build enriched link text for a Jira issue.\"\"\"
    title_part = escape_md_link_text(truncate(summary)) if summary else ''
    if title_part and issue_type:
        return f'{key} ({issue_type}): {title_part}'
    elif title_part:
        return f'{key}: {title_part}'
    elif issue_type:
        return f'{key} ({issue_type})'
    return key

def shorten_github_pr(url):
    \"\"\"Extract repo#number from a GitHub PR URL.\"\"\"
    m = re.match(r'https?://github\.com/[^/]+/([^/]+)/pull/(\d+)', url)
    if m:
        return m.group(1) + '#' + m.group(2)
    return None

def shorten_jira(url, skip_enrich=False):
    \"\"\"Extract issue key from a Jira URL and look up metadata.\"\"\"
    m = re.match(r'https?://[^/]+/browse/([A-Z]+-\d+)', url)
    if not m:
        return None
    key = m.group(1)
    if skip_enrich:
        return key
    info = lookup_jira(key)
    if info and info[1]:
        return format_jira_label(key, *info)
    return key

def shorten_slack(url):
    \"\"\"Return 'Slack thread' for any Slack URL.\"\"\"
    if re.match(r'https?://[^/]*slack\.com/', url):
        return 'Slack thread'
    return None

def shorten_url(url, skip_enrich=False):
    \"\"\"Return a short label for a URL, or None if not a recognized type.\"\"\"
    return shorten_github_pr(url) or shorten_jira(url, skip_enrich=skip_enrich) or shorten_slack(url)

def is_bare_url(text):
    \"\"\"Check if text is just a URL (possibly with trailing whitespace/punctuation stripped).\"\"\"
    text = text.strip()
    return text.startswith('http://') or text.startswith('https://')

changes = []

# --- Pass 1: Markdown links with URL as link text or bare Jira key ---
# Match [text](url) where the link text is a URL or just a Jira key
# We iterate manually instead of using re.sub so we can track positions
# accurately even as we modify the content.
md_link_re = re.compile(r'\[([^\]]+)\]\(([^)]+)\)')
offset = 0
for m in list(md_link_re.finditer(content)):
    text = m.group(1)
    url = m.group(2)
    start = m.start() + offset
    end = m.end() + offset
    skip = should_skip_enrichment(content, start)
    replacement = None
    if is_bare_url(text):
        short = shorten_url(url, skip_enrich=skip)
        if short:
            changes.append(('md-link', url, short))
            replacement = '[' + short + '](' + url + ')'
    elif re.match(r'^[A-Z]+-\d+$', text.strip()):
        # Link text is just a Jira key — enrich with type and title
        if not skip:
            jira_key = text.strip()
            jira_m = re.match(r'https?://[^/]+/browse/([A-Z]+-\d+)', url)
            if jira_m and jira_m.group(1) == jira_key:
                info = lookup_jira(jira_key)
                if info and info[1]:
                    short = format_jira_label(jira_key, *info)
                    if short != jira_key:
                        changes.append(('enrich', url, short))
                        replacement = '[' + short + '](' + url + ')'
    if replacement:
        content = content[:start] + replacement + content[end:]
        offset += len(replacement) - (m.end() - m.start())

# --- Pass 2: HTML links with URL as link text ---
# Match <a href=\"url\">url</a>
html_link_re = re.compile(r'<a\s+href=\"([^\"]+)\">([^<]+)</a>', re.IGNORECASE)
offset = 0
for m in list(html_link_re.finditer(content)):
    url = m.group(1)
    text = m.group(2)
    start = m.start() + offset
    end = m.end() + offset
    if is_bare_url(text):
        skip = should_skip_enrichment(content, start)
        short = shorten_url(url, skip_enrich=skip)
        if short:
            changes.append(('html-link', url, short))
            replacement = '[' + short + '](' + url + ')'
            content = content[:start] + replacement + content[end:]
            offset += len(replacement) - (m.end() - m.start())

# --- Pass 3: Bare URLs not inside markdown link syntax ---
# We need to match URLs that are NOT already inside [...](...) or <a> tags.
# Strategy: find all URLs, check surrounding context.

github_pr_pattern = r'https?://github\.com/[^\s\)>\]]+/pull/\d+'
jira_pattern = r'https?://[^\s\)>\]]*?/browse/[A-Z]+-\d+'
slack_pattern = r'https?://[^\s\)>\]]*?slack\.com/[^\s\)>\]]+'
url_pattern = '(' + github_pr_pattern + '|' + jira_pattern + '|' + slack_pattern + ')'

def fix_bare_urls(content):
    result = []
    last_end = 0
    for m in re.finditer(url_pattern, content):
        start = m.start()
        end = m.end()
        url = m.group(0)

        # Check if this URL is already inside a markdown link
        # Look for ]( immediately before, or [ before with ] after
        before = content[max(0, start-2):start]
        if before.endswith(']('):
            result.append(content[last_end:end])
            last_end = end
            continue

        # Check if inside [text](url) — look back for unmatched [
        prefix = content[max(0, start-500):start]
        # Find the last [ that isn't closed by ]
        bracket_depth = 0
        for ch in reversed(prefix):
            if ch == ']':
                bracket_depth += 1
            elif ch == '[':
                if bracket_depth > 0:
                    bracket_depth -= 1
                else:
                    # Unclosed [ — we might be in link text, skip
                    break
        # Actually, the above is for link text. For the URL part, check ](
        # More reliable: check if ]( appears right before the URL
        # We already checked that. Also check if we're inside an href=\"\"
        if '\"' in before and 'href' in content[max(0, start-20):start]:
            result.append(content[last_end:end])
            last_end = end
            continue

        skip = should_skip_enrichment(content, start)
        short = shorten_url(url, skip_enrich=skip)
        if short:
            changes.append(('bare', url, short))
            result.append(content[last_end:start])
            result.append('[' + short + '](' + url + ')')
            last_end = end
        else:
            result.append(content[last_end:end])
            last_end = end

    result.append(content[last_end:])
    return ''.join(result)

content = fix_bare_urls(content)

# --- Report and write ---

if not changes:
    print('No links to clean up.')
    sys.exit(0)

for kind, url, short in changes:
    if kind == 'bare':
        print(f'  bare URL -> [{short}]({url})')
    elif kind == 'md-link':
        print(f'  [url](url) -> [{short}]({url})')
    elif kind == 'html-link':
        print(f'  <a>url</a> -> [{short}]({url})')
    elif kind == 'enrich':
        print(f'  [key](url) -> [{short}]({url})')

print(f'\n{len(changes)} link(s) cleaned up.')

if dry_run:
    print('\n(dry run - no changes written)')
else:
    with open(filepath, 'w') as f:
        f.write(content)
    print('Daily note updated.')
" "$daily_note" "$DRY_RUN" "$JIRA_HOST" "$JIRA_EMAIL" "$JIRA_API_TOKEN"
