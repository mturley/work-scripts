#!/usr/bin/env bash
# List Claude Code sessions across all projects, most recent first.
# Shows session ID, working directory, first and last user messages with timestamps.
# Interactive: pages 5 at a time, press Enter for more.
# --find "text": Search for sessions containing the given text in messages

set -uo pipefail

PAGE_SIZE=5
sessions_dir="$HOME/.claude/projects"

# If an argument is given, use it as search text
search_text="${1:-}"

if [[ ! -d "$sessions_dir" ]]; then
  echo "No Claude sessions found at $sessions_dir"
  exit 1
fi

# Collect all session files sorted by modification time (most recent first)
files=()
while IFS= read -r line; do
  files+=("$line")
done < <(ls -t "$sessions_dir"/*/*.jsonl 2>/dev/null)

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No Claude sessions found."
  exit 0
fi

total=${#files[@]}

if [[ -n "$search_text" ]]; then
  # Find mode: search through sessions for matching text
  for (( i = 0; i < total; i++ )); do
    f="${files[$i]}"

    # Show spinner
    printf "\rSearching... [%d/%d]" $((i + 1)) "$total" >&2

    # Extract messages and check for match
    match_found=false
    eval "$(python3 -c "
import json,re,shlex,sys
from datetime import datetime,timezone
search='${search_text}'
search_lower=search.lower()
first=''
first_ts=''
last=''
last_ts=''
match=False
skip_prefixes=('Set model to','model ','Caveat:','env ')
for line in open('$f'):
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
        if search_lower in t.lower():
            match=True
    except: pass
print(f'match_found={str(match).lower()}')
print(f'name={shlex.quote(first[:80])}')
print(f'name_ts={shlex.quote(first_ts)}')
print(f'msg={shlex.quote(last[:120])}')
print(f'msg_ts={shlex.quote(last_ts)}')
" 2>/dev/null)" || true

    if [[ "$match_found" == "true" ]]; then
      # Clear spinner line
      printf "\r%*s\r" 50 "" >&2

      sid=$(basename "$f" .jsonl)
      cwd=$(grep -o '"cwd":"[^"]*"' "$f" | head -1 | cut -d'"' -f4)
      cwd="${cwd/#$HOME/~}"

      echo "$sid  $cwd"
      [[ -n "$name" ]] && echo "  ┌─ Prompt ($name_ts):  $name"
      if [[ -n "$msg" ]]; then
        if [[ "$msg" != "$name" ]]; then
          echo "  └─ Latest ($msg_ts):  $msg"
        else
          echo "  └─ (single message)"
        fi
      fi
      echo

      # Check if there are more sessions to search
      if (( i + 1 < total )); then
        read -rp "Enter to keep looking " </dev/tty
      fi
    fi
  done

  # Clear spinner line
  printf "\r%*s\r" 50 "" >&2

  # If we got here without finding anything, all sessions were checked
  if [[ "$match_found" != "true" ]]; then
    echo "No matches found"
  fi
else
  # Normal mode: page through sessions
  offset=0

  while (( offset < total )); do
    end=$(( offset + PAGE_SIZE ))
    if (( end > total )); then
      end=$total
    fi

    for (( i = offset; i < end; i++ )); do
      f="${files[$i]}"
      sid=$(basename "$f" .jsonl)
      cwd=$(grep -o '"cwd":"[^"]*"' "$f" | head -1 | cut -d'"' -f4)
      cwd="${cwd/#$HOME/~}"

      name=""
      name_ts=""
      msg=""
      msg_ts=""
      eval "$(python3 -c "
import json,re,shlex
from datetime import datetime,timezone
first=''
first_ts=''
last=''
last_ts=''
skip_prefixes=('Set model to','model ','Caveat:','env ')
for line in open('$f'):
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
    except: pass
print(f'name={shlex.quote(first[:80])}')
print(f'name_ts={shlex.quote(first_ts)}')
print(f'msg={shlex.quote(last[:120])}')
print(f'msg_ts={shlex.quote(last_ts)}')
" 2>/dev/null)" || true

      echo "$sid  $cwd"
      [[ -n "$name" ]] && echo "  ┌─ Prompt ($name_ts):  $name"
      if [[ -n "$msg" ]]; then
        if [[ "$msg" != "$name" ]]; then
          echo "  └─ Latest ($msg_ts):  $msg"
        else
          echo "  └─ (single message)"
        fi
      fi
      echo
    done

    offset=$end

    if (( offset < total )); then
      remaining=$(( total - offset ))
      read -rp "[Enter for more ($remaining remaining)] " </dev/tty
    fi
  done
fi
