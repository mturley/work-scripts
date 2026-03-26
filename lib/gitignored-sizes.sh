#!/usr/bin/env bash
# gitignored-sizes.sh - Show total size of gitignored files/directories
#
# Usage: gitignored-sizes.sh <repo-root>
#
# Output: Total size and count of gitignored entries (e.g. "1.3G across 12 entries").
# If no gitignored entries exist, outputs nothing and exits with code 0.

set -euo pipefail

REPO_ROOT="${1:?Usage: gitignored-sizes.sh <repo-root>}"

# Get list of top-level gitignored files/directories
ENTRIES=$(git -C "$REPO_ROOT" ls-files --others --ignored --exclude-standard --directory --no-empty-directory 2>/dev/null)

if [ -z "$ENTRIES" ]; then
  exit 0
fi

# Build array of full paths that actually exist
PATHS=()
while IFS= read -r entry; do
  full_path="${REPO_ROOT}/${entry}"
  if [ -e "$full_path" ]; then
    PATHS+=("$full_path")
  fi
done <<< "$ENTRIES"

if [ ${#PATHS[@]} -eq 0 ]; then
  exit 0
fi

# Show total size
TOTAL="$(du -sh -c "${PATHS[@]}" 2>/dev/null | tail -1 | cut -f1)"
echo "${TOTAL} across ${#PATHS[@]} entries"
