#!/usr/bin/env bash
# copy-worktree-files.sh - Copy useful files from one worktree to another
#
# Usage:
#   copy-worktree-files.sh --list <source-root>
#   copy-worktree-files.sh --copy <source-root> <dest-root> <rel-path>...
#
# Targets: node_modules/ directories, build output directories (dist/, bin/),
# and top-level dotfiles/dotdirs (config like .env.local, .husky, etc.).
#
# --list: prints relative paths of copyable targets, one per line.
# --copy: copies the specified relative paths from source to dest.

set -euo pipefail

MODE="${1:?Usage: copy-worktree-files.sh <--list|--copy> <source-root> ...}"
SOURCE_ROOT="${2:?Missing source root}"

case "$MODE" in
  --list)
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

    # Top-level dotfiles and dotdirs (excluding .git)
    for f in "$SOURCE_ROOT"/.*; do
      [ -e "$f" ] || continue
      base="$(basename "$f")"
      case "$base" in
        .|..|.git) continue ;;
      esac
      echo "$base"
    done
    ;;

  --copy)
    DEST_ROOT="${3:?Missing dest root}"
    shift 3
    if [ $# -eq 0 ]; then
      echo "No paths specified to copy."
      exit 0
    fi

    COPIED=0
    ERRORS=0

    for rel in "$@"; do
      src="${SOURCE_ROOT}/${rel}"
      dest="${DEST_ROOT}/${rel}"

      if [ ! -e "$src" ]; then
        echo "  SKIP (not found): $rel"
        continue
      fi

      mkdir -p "$(dirname "$dest")"

      echo "  Copying ${rel}..."
      if [ -d "$src" ]; then
        if rsync -a "$src/" "$dest/" 2>/dev/null; then
          COPIED=$((COPIED + 1))
        else
          echo "  ERROR: $rel" >&2
          ERRORS=$((ERRORS + 1))
        fi
      else
        if cp "$src" "$dest" 2>/dev/null; then
          COPIED=$((COPIED + 1))
        else
          echo "  ERROR: $rel" >&2
          ERRORS=$((ERRORS + 1))
        fi
      fi
    done

    echo "Copied ${COPIED} entries."
    if [ "$ERRORS" -gt 0 ]; then
      echo "Errors: ${ERRORS}." >&2
    fi
    ;;

  *)
    echo "Unknown mode: $MODE. Use --list or --copy." >&2
    exit 1
    ;;
esac
