#!/usr/bin/env bash
#
# clean-node-modules — recursively find and delete node_modules folders.
#
# Scans a directory (default: current directory) for node_modules folders,
# lists them with their sizes, asks for confirmation, then deletes them all
# with verbose output.
#
# Usage: clean-node-modules [DIR]
#

set -euo pipefail

usage() {
  cat <<'EOF'
clean-node-modules — recursively find and delete node_modules folders.

Usage:
  clean-node-modules [DIR]

Arguments:
  DIR    Directory to scan (default: current directory)

Scans DIR recursively for node_modules folders, lists them with their
sizes, asks for confirmation, then deletes them all with verbose output.
EOF
}

# ── Parse arguments ─────────────────────────────────────────────────────

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

TARGET_DIR="${1:-.}"

if [ ! -d "$TARGET_DIR" ]; then
  echo "Error: not a directory: $TARGET_DIR" >&2
  exit 1
fi

# ── Find node_modules folders ───────────────────────────────────────────

# -prune stops find from descending into a node_modules once found, so we
# don't list nested node_modules inside one that's already slated for
# deletion. Populate a bash-3.2-compatible array via a while-read loop.
dirs=()
while IFS= read -r dir; do
  dirs+=("$dir")
done < <(find "$TARGET_DIR" -type d -name node_modules -prune)

if [ "${#dirs[@]}" -eq 0 ]; then
  echo "No node_modules folders found in: $TARGET_DIR"
  exit 0
fi

# ── List them ───────────────────────────────────────────────────────────

echo "Found ${#dirs[@]} node_modules folder(s) in $TARGET_DIR:"
echo
for dir in "${dirs[@]}"; do
  size=$(du -sh "$dir" 2>/dev/null | cut -f1)
  printf '  %s\t%s\n' "${size:-?}" "$dir"
done
echo

# ── Confirm ─────────────────────────────────────────────────────────────

printf 'Delete all %d node_modules folder(s)? [y/N] ' "${#dirs[@]}"
read -r reply
case "$reply" in
  y|Y|yes|Yes|YES)
    ;;
  *)
    echo "Aborted. Nothing deleted."
    exit 0
    ;;
esac

# ── Delete ──────────────────────────────────────────────────────────────

echo
for dir in "${dirs[@]}"; do
  rm -rfv "$dir"
done
echo
echo "Done. Deleted ${#dirs[@]} node_modules folder(s)."
