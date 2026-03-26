#!/usr/bin/env bash
# copy-worktree-files.sh - Copy useful files from one worktree to another
#
# Usage:
#   copy-worktree-files.sh --summarize <source-root>
#   copy-worktree-files.sh --copy <source-root> <dest-root>
#
# Targets: node_modules/ directories, build output directories (dist/, bin/),
# and top-level dotfiles/dotdirs (config like .env.local, .husky, etc.).
#
# --summarize: lists targets found, or nothing if none exist.
# --copy: copies targets to matching relative paths in dest, prints progress.

set -euo pipefail

MODE="${1:?Usage: copy-worktree-files.sh <--summarize|--copy> <source-root> [dest-root]}"
SOURCE_ROOT="${2:?Missing source root}"

# Find copyable targets — outputs paths relative to SOURCE_ROOT
find_targets() {
  local root="$1"

  # node_modules dirs (prune to avoid recursing into them)
  find "$root" -path "*/.git" -prune -o \
    -name node_modules -type d -prune -print \
    2>/dev/null | while IFS= read -r p; do
    echo "${p#"$root"/}"
  done

  # dist/ and bin/ build output dirs (shallow, skip node_modules and .git)
  find "$root" -maxdepth 3 \
    -path "*/.git" -prune -o \
    -path "*/node_modules" -prune -o \
    \( -name dist -o -name bin \) -type d -print \
    2>/dev/null | while IFS= read -r p; do
    echo "${p#"$root"/}"
  done

  # Top-level dotfiles and dotdirs (excluding .git)
  for f in "$root"/.*; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    case "$base" in
      .|..|.git) continue ;;
    esac
    echo "$base"
  done
}

case "$MODE" in
  --summarize)
    TARGETS="$(find_targets "$SOURCE_ROOT")"
    if [ -z "$TARGETS" ]; then
      exit 0
    fi
    COUNT="$(echo "$TARGETS" | wc -l | tr -d ' ')"
    echo "${COUNT} entries (node_modules, build outputs, dotfiles)"
    ;;

  --copy)
    DEST_ROOT="${3:?Missing dest root}"
    TARGETS="$(find_targets "$SOURCE_ROOT")"
    if [ -z "$TARGETS" ]; then
      echo "No files to copy."
      exit 0
    fi

    COPIED=0
    ERRORS=0

    while IFS= read -r rel; do
      src="${SOURCE_ROOT}/${rel}"
      dest="${DEST_ROOT}/${rel}"

      mkdir -p "$(dirname "$dest")"

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
    done <<< "$TARGETS"

    echo "Copied ${COPIED} entries."
    if [ "$ERRORS" -gt 0 ]; then
      echo "Errors: ${ERRORS}." >&2
    fi
    ;;

  *)
    echo "Unknown mode: $MODE. Use --summarize or --copy." >&2
    exit 1
    ;;
esac
