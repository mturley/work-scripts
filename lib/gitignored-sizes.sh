#!/usr/bin/env bash
# gitignored-sizes.sh - List gitignored files/directories with their disk usage
#
# Usage: gitignored-sizes.sh <repo-root>
#
# Output: One line per entry with size and path, plus a total line.
# If no gitignored entries exist, outputs nothing and exits with code 0.
#
# Example output:
#   1.2G	node_modules/
#   45M	.cache/
#   2.1K	.env.local
#   ---
#   1.3G	total

set -euo pipefail

REPO_ROOT="${1:?Usage: gitignored-sizes.sh <repo-root>}"

# Get list of top-level gitignored files/directories
ENTRIES=$(git -C "$REPO_ROOT" ls-files --others --ignored --exclude-standard --directory 2>/dev/null)

if [ -z "$ENTRIES" ]; then
  exit 0
fi

# Build array of full paths that actually exist
PATHS=()
while IFS= read -r entry; do
  full_path="${REPO_ROOT}/${entry}"
  # Skip .claude/worktrees/ — these are other worktrees, not dependencies
  if [[ "$entry" == .claude/worktrees/* || "$entry" == .claude/worktrees/ ]]; then
    continue
  fi
  if [ -e "$full_path" ]; then
    PATHS+=("$full_path")
  fi
done <<< "$ENTRIES"

if [ ${#PATHS[@]} -eq 0 ]; then
  exit 0
fi

# Show individual sizes and total
du -sh "${PATHS[@]}" 2>/dev/null
echo "---"
du -sh -c "${PATHS[@]}" 2>/dev/null | tail -1
