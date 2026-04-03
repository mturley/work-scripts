#!/usr/bin/env bash
# link-worktree-files.sh - Link useful files from one worktree to another
#
# Usage:
#   link-worktree-files.sh --list <source-root>
#   link-worktree-files.sh --link <source-root> <dest-root> <rel-path>...
#
# Targets: node_modules/ directories, build output directories (dist/, bin/),
# and top-level dotfiles/dotdirs (config like .env.local, .husky, etc.).
#
# --list: prints relative paths of linkable targets, one per line.
# --link: links the specified relative paths from source to dest.

set -euo pipefail

MODE="${1:?Usage: link-worktree-files.sh <--list|--link> <source-root> ...}"
SOURCE_ROOT="${2:?Missing source root}"

case "$MODE" in
  --list-dirs)
    # node_modules dirs (prune to avoid recursing into them)
    find "$SOURCE_ROOT" -path "*/.git" -prune -o \
      -name node_modules -type d -prune -print \
      2>/dev/null | while IFS= read -r p; do
      echo "${p#"$SOURCE_ROOT"/}"
    done

    # dist/ and bin/ build output dirs (shallow, skip node_modules and .git)
    find "$SOURCE_ROOT" -maxdepth 3 \
      -path "*/.git" -prune -o \
      -path "*/node_modules" -prune -o \
      \( -name dist -o -name bin \) -type d -print \
      2>/dev/null | while IFS= read -r p; do
      echo "${p#"$SOURCE_ROOT"/}"
    done
    ;;

  --list-dotfiles)
    # Top-level dotfiles and dotdirs that are gitignored (excluding .git)
    for f in "$SOURCE_ROOT"/.*; do
      [ -e "$f" ] || continue
      base="$(basename "$f")"
      case "$base" in
        .|..|.git) continue ;;
      esac
      if git -C "$SOURCE_ROOT" check-ignore -q "$base" 2>/dev/null; then
        echo "$base"
      fi
    done
    ;;

  --link)
    DEST_ROOT="${3:?Missing dest root}"
    shift 3
    if [ $# -eq 0 ]; then
      echo "No paths specified to link."
      exit 0
    fi

    LINKED=0
    ERRORS=0

    for rel in "$@"; do
      src="${SOURCE_ROOT}/${rel}"
      dest="${DEST_ROOT}/${rel}"

      if [ ! -e "$src" ]; then
        echo "  SKIP (not found): $rel"
        continue
      fi

      mkdir -p "$(dirname "$dest")"

      # Remove any existing target first (stale symlink, empty dir, or old copy).
      if [ -L "$dest" ] || [ -e "$dest" ]; then
        rm -rf "$dest"
      fi

      echo "  Linking ${rel}..."
      if ln -s "$src" "$dest" 2>/dev/null; then
        LINKED=$((LINKED + 1))
      else
        echo "  ERROR: $rel" >&2
        ERRORS=$((ERRORS + 1))
      fi
    done

    echo "Linked ${LINKED} entries."
    if [ "$ERRORS" -gt 0 ]; then
      echo "Errors: ${ERRORS}." >&2
    fi
    ;;

  *)
    echo "Unknown mode: $MODE. Use --list-dirs, --list-dotfiles, or --link." >&2
    exit 1
    ;;
esac
