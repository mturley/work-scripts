# prep

Copy focus and deferred items from the most recent previous daily note to today's [Obsidian daily note](https://obsidian.md/help/plugins/daily-notes). Designed to be the first thing you run each morning.

```bash
prep         # copy items from the previous note to today
prep help    # show usage
```

## What it does

1. Ensures today's daily note exists (creates it from template if not)
2. Finds the most recent previous daily note (handles gaps and weekends)
3. Checks if `eod` was run on the previous note — warns if not, but lets you continue
4. Copies all items from the previous note's "tomorrow's focus" (or "monday's focus") section into today's "today's focus" section
5. Copies all items from the previous note's "deferring for later" section into today's "deferring for later" section
6. Removes blank checkbox lines left over from templates
7. Checks off the "Copy focus items and deferred items from yesterday's notes" checkbox
8. Opens the daily note in Obsidian

Items are appended after any existing content in each section. Existing items in today's note are never modified or removed.

## Daily note template

Both `prep` and `eod` rely on specific section headings in your Obsidian daily note template. The sections they look for:

```markdown
## ⏳ Prep for the day

- [ ] Copy focus items and deferred items from yesterday's notes (run `prep`)
- [ ] ...

---
## ❯❯❯❯ 🗓️ Today's focus

- [ ] ...
### ... and if there's time:
- [ ] Set up tomorrow's focus (run `eod`)
- [ ] ...

---
## ↪ 🗓️ Tomorrow's focus

- [ ] 

----
## 💤 Deferring for later

- [ ] 
```

The heading text can include emoji and other decoration — the scripts match on the key phrases ("Today's focus", "Tomorrow's focus", "Monday's focus", "Deferring for later", "Prep for the day", "and if there's time"). The checkboxes for "Copy focus items" and "Set up tomorrow's focus" must contain those phrases to be checked off automatically.

## Setup

1. Enable the Obsidian CLI: Obsidian -> Settings -> General -> Advanced
2. Set `OBSIDIAN_VAULT` in your `.env` file (see [worklog setup](worklog.md#setup))
