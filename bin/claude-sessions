#!/usr/bin/env bash
# List Claude Code sessions across all projects, most recent first.
# Shows session ID, working directory, first and last user messages with timestamps.
# Interactive: pages 5 at a time, press Enter for more.

set -uo pipefail

PAGE_SIZE=5
sessions_dir="$HOME/.claude/projects"

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
