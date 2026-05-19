#!/usr/bin/env bash
# claude-sessions.sh - Shared functions for Claude Code session lookup

CLAUDE_SESSIONS_DIR="$HOME/.claude/projects"

# claude_sessions_collect
# Populates the global array claude_session_files with all session JSONL files,
# sorted by modification time (most recent first).
# Returns 1 if no sessions found.
claude_sessions_collect() {
  claude_session_files=()
  if [[ ! -d "$CLAUDE_SESSIONS_DIR" ]]; then
    return 1
  fi
  while IFS= read -r line; do
    claude_session_files+=("$line")
  done < <(ls -t "$CLAUDE_SESSIONS_DIR"/*/*.jsonl 2>/dev/null)
  [[ ${#claude_session_files[@]} -gt 0 ]]
}

# _claude_session_python <file> [search_text]
# Internal: runs the Python parser on a session file.
# If search_text is provided, also checks for a match.
# Sets: cs_name, cs_name_ts, cs_msg, cs_msg_ts, and optionally cs_match.
_claude_session_python() {
  local f="$1"
  local search="${2:-}"
  cs_name=""
  cs_name_ts=""
  cs_msg=""
  cs_msg_ts=""
  cs_match=false
  eval "$(CS_FILE="$f" CS_SEARCH="$search" python3 -c "
import json,re,shlex,os
from datetime import datetime,timezone
filepath=os.environ['CS_FILE']
search=os.environ.get('CS_SEARCH','')
search_lower=search.lower() if search else ''
first=''
first_ts=''
last=''
last_ts=''
match=False
skip_prefixes=('Set model to','model ','Caveat:','env ')
for line in open(filepath):
    try:
        obj=json.loads(line)
        if obj.get('isMeta'): continue
        m=obj.get('message',{})
        if m.get('role')!='user': continue
        c=m.get('content','')
        if isinstance(c,str):
            t=c.strip()
        elif isinstance(c,list):
            t=' '.join(x.get('text','') for x in c if isinstance(x,dict) and x.get('type')=='text').strip()
        else: continue
        t=re.sub(r'<[^>]+>','',t).strip()
        t=' '.join(t.split())
        if not t or t.startswith('/') or t.startswith('[Request'): continue
        if any(t.startswith(p) for p in skip_prefixes): continue
        ts=obj.get('timestamp','')
        if ts:
            try:
                dt=datetime.fromisoformat(ts.replace('Z','+00:00')).astimezone()
                ts=dt.strftime('%Y-%m-%d %H:%M')
            except: pass
        if not first:
            first=t
            first_ts=ts
        last=t
        last_ts=ts
        if search_lower and search_lower in t.lower():
            match=True
    except: pass
if search:
    print(f'cs_match={str(match).lower()}')
print(f'cs_name={shlex.quote(first[:80])}')
print(f'cs_name_ts={shlex.quote(first_ts)}')
print(f'cs_msg={shlex.quote(last[:120])}')
print(f'cs_msg_ts={shlex.quote(last_ts)}')
" 2>/dev/null)" || true
}

# claude_session_parse <file>
# Parses a session JSONL file and sets:
#   cs_name, cs_name_ts, cs_msg, cs_msg_ts
claude_session_parse() {
  _claude_session_python "$1"
}

# claude_session_parse_search <file> <search_text>
# Like claude_session_parse, but also sets cs_match (true/false) indicating
# whether any user message contains search_text (case-insensitive).
claude_session_parse_search() {
  _claude_session_python "$1" "$2"
}

# claude_session_display <file> [fd]
# Displays a formatted session entry (ID, cwd, first/last messages).
# Requires cs_name/cs_name_ts/cs_msg/cs_msg_ts to be set (call parse first).
# Output goes to the given file descriptor (default: 1 = stdout).
claude_session_display() {
  local f="$1"
  local fd="${2:-1}"
  local sid cwd
  sid=$(basename "$f" .jsonl)
  cwd=$(grep -o '"cwd":"[^"]*"' "$f" | head -1 | cut -d'"' -f4)
  cwd="${cwd/#$HOME/~}"

  echo "$sid  $cwd" >&"$fd"
  [[ -n "$cs_name" ]] && echo "  ┌─ Prompt ($cs_name_ts):  $cs_name" >&"$fd"
  if [[ -n "$cs_msg" ]]; then
    if [[ "$cs_msg" != "$cs_name" ]]; then
      echo "  └─ Latest ($cs_msg_ts):  $cs_msg" >&"$fd"
    else
      echo "  └─ (single message)" >&"$fd"
    fi
  fi
  echo >&"$fd"
}

# claude_session_find_file <session_id>
# Finds the JSONL file for a given session ID. Prints the path or empty string.
claude_session_find_file() {
  find "$CLAUDE_SESSIONS_DIR" -name "$1.jsonl" 2>/dev/null | head -1
}

# claude_session_cwd <file>
# Extracts the working directory from a session file. Prints the path.
claude_session_cwd() {
  grep -o '"cwd":"[^"]*"' "$1" | head -1 | cut -d'"' -f4
}
