#!/usr/bin/env bash
# copy-gitignored.sh - Copy gitignored files from one worktree to another
#
# Usage: copy-gitignored.sh <source-root> <dest-root>
#
# Copies all gitignored files/directories from the source working tree
# to the same relative paths in the destination using rsync.
# Reports what was copied and any errors.

set -euo pipefail

SOURCE_ROOT="${1:?Usage: copy-gitignored.sh <source-root> <dest-root>}"
DEST_ROOT="${2:?Usage: copy-gitignored.sh <source-root> <dest-root>}"

# Get list of top-level gitignored files/directories
ENTRIES=$(git -C "$SOURCE_ROOT" ls-files --others --ignored --exclude-standard --directory 2>/dev/null)

if [ -z "$ENTRIES" ]; then
  echo "No gitignored files found."
  exit 0
fi

COPIED=0
ERRORS=0

while IFS= read -r entry; do
  src="${SOURCE_ROOT}/${entry}"
  dest="${DEST_ROOT}/${entry}"

  # Skip .claude/worktrees/ — these are other worktrees, not dependencies
  if [[ "$entry" == .claude/worktrees/* || "$entry" == .claude/worktrees/ ]]; then
    continue
  fi

  if [ ! -e "$src" ]; then
    continue
  fi

  # Ensure destination parent directory exists
  mkdir -p "$(dirname "$dest")"

  if [ -d "$src" ]; then
    # For directories, use rsync (handles trailing slashes correctly)
    if rsync -a "$src" "$(dirname "$dest")/" 2>/dev/null; then
      echo "Copied: $entry"
      COPIED=$((COPIED + 1))
    else
      echo "ERROR copying: $entry" >&2
      ERRORS=$((ERRORS + 1))
    fi
  else
    # For files, use cp
    if cp "$src" "$dest" 2>/dev/null; then
      echo "Copied: $entry"
      COPIED=$((COPIED + 1))
    else
      echo "ERROR copying: $entry" >&2
      ERRORS=$((ERRORS + 1))
    fi
  fi
done <<< "$ENTRIES"

echo "---"
echo "Copied $COPIED entries. Errors: $ERRORS."
