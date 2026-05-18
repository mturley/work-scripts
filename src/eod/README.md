# eod

Set up tomorrow's focus by carrying over unchecked items from today's [Obsidian daily note](https://obsidian.md/help/plugins/daily-notes). Designed to be the last thing you run each day.

```bash
eod                # process today's note
eod yesterday      # process the most recent previous note
eod friday         # process the most recent Friday note (handy on Monday)
eod "Apr 3"        # process a specific date
eod help           # show usage
```

## What it does

1. Extracts all unchecked items from the target note's "today's focus" section
   - Excludes items from the "prep for the day" section
   - Excludes items from the "and if there's time" subsection
   - Preserves sub-items and indentation
2. Appends the unchecked items to the "tomorrow's focus" (or "monday's focus") section
3. If the target note is a Friday, renames "tomorrow's focus" to "monday's focus"
4. Removes blank checkbox lines left over from templates
5. Checks off the "Set up tomorrow's focus" checkbox
6. Opens the daily note in Obsidian

Items are appended after any existing content in the section. Existing items are never modified or removed.

## Date argument

The date argument does a case-insensitive match against daily note filenames (e.g. `2026.093 - Friday Apr 3 - Work Notes.md`), so you can use:

- Day names: `friday`, `Thursday`
- Month and day: `"Apr 3"`, `"Mar 26"`
- Ordinal day: `2026.093`
- `yesterday` — shortcut for the most recent note before today

When multiple notes match, the most recent one is used.

## Daily note template

Both `prep` and `eod` rely on specific section headings in your Obsidian daily note template. See [prep.md](prep.md#daily-note-template) for the expected structure and which phrases the scripts match on.

## Setup

1. Enable the Obsidian CLI: Obsidian -> Settings -> General -> Advanced
2. Set `OBSIDIAN_VAULT` in your `.env` file (see [worklog setup](worklog.md#setup))
