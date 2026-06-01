#!/usr/bin/env bash
# clone-worktree-files.sh - Clone useful files from one worktree to another
#
# Usage:
#   clone-worktree-files.sh --list <source-root>
#   clone-worktree-files.sh --clone <source-root> <dest-root> <rel-path>...
#
# Targets: node_modules/ directories, build output directories (dist/, bin/),
# and top-level dotfiles/dotdirs (config like .env.local, .husky, etc.).
#
# --list: prints relative paths of cloneable targets, one per line.
# --clone: clones the specified relative paths from source to dest.
#
# Copy strategy (detected once at runtime):
#   macOS (APFS) — uses `cp -Rc` for copy-on-write clones.
#   Other platforms — uses `rsync -a` for full copies. Slower, but each copy
#     is fully independent.
#
# Because all targets are real copies (not symlinks), the repo's existing
# .gitignore rules handle them — no .git/info/exclude management needed.

set -euo pipefail

COLOR_RED="$(tput setaf 1 2>/dev/null || true)"
COLOR_RESET="$(tput sgr0 2>/dev/null || true)"

MODE="${1:?Usage: clone-worktree-files.sh <--list-dirs|--list-dotfiles|--clone> <source-root> ...}"
SOURCE_ROOT="${2:?Missing source root}"

case "$MODE" in
  --list-dirs)
    # node_modules dirs (prune to avoid recursing into them)
    find "$SOURCE_ROOT" \
      -path "*/.git" -prune -o \
      -path "*/.worktrees" -prune -o \
      -path "*/.claude/worktrees" -prune -o \
      -name node_modules -type d -prune -print \
      2>/dev/null | while IFS= read -r p; do
      echo "${p#"$SOURCE_ROOT"/}"
    done

    # dist/ and bin/ build output dirs (skip node_modules, .git, and worktrees)
    # Skip directories that contain tracked files (cloning over them would
    # cause git to report tracked files as deleted).
    find "$SOURCE_ROOT" \
      -path "*/.git" -prune -o \
      -path "*/node_modules" -prune -o \
      -path "*/.worktrees" -prune -o \
      -path "*/.claude/worktrees" -prune -o \
      \( -name dist -o -name bin \) -type d -print \
      2>/dev/null | while IFS= read -r p; do
      rel="${p#"$SOURCE_ROOT"/}"
      # Check if any tracked files exist under this directory
      if [ -z "$(git -C "$SOURCE_ROOT" ls-files "$rel" 2>/dev/null)" ]; then
        echo "$rel"
      fi
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

  --clone)
    DEST_ROOT="${3:?Missing dest root}"
    shift 3
    if [ $# -eq 0 ]; then
      echo "No paths specified to clone."
      exit 0
    fi

    # Detect copy strategy once
    IS_MAC=false
    if [ "$(uname -s)" = "Darwin" ]; then
      IS_MAC=true
      echo "Using APFS copy-on-write clones (cp -Rc)."
    fi

    DONE=0
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

      if $IS_MAC; then
        # macOS APFS: copy-on-write clone
        printf "  Cloning ${rel}... "
        cp -Rc "$src" "$dest" 2>/dev/null &
        BG_PID=$!
        SPIN_CHARS='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
        SPIN_I=0
        while kill -0 "$BG_PID" 2>/dev/null; do
          printf "\b${SPIN_CHARS:$SPIN_I:1}"
          SPIN_I=$(( (SPIN_I + 1) % ${#SPIN_CHARS} ))
          sleep 0.1
        done
        printf "\b"
        if wait "$BG_PID"; then
          echo "done"
          DONE=$((DONE + 1))
        else
          echo "ERROR" >&2
          ERRORS=$((ERRORS + 1))
        fi
      else
        # Non-macOS: full copy via rsync with a spinner
        printf "  Copying ${rel}... "
        rsync -a "$src/" "$dest/" 2>/dev/null &
        BG_PID=$!
        SPIN_CHARS='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
        SPIN_I=0
        while kill -0 "$BG_PID" 2>/dev/null; do
          printf "\b${SPIN_CHARS:$SPIN_I:1}"
          SPIN_I=$(( (SPIN_I + 1) % ${#SPIN_CHARS} ))
          sleep 0.1
        done
        printf "\b"
        if wait "$BG_PID"; then
          echo "done"
          DONE=$((DONE + 1))
        else
          echo "ERROR" >&2
          ERRORS=$((ERRORS + 1))
        fi
      fi
    done

    echo "Done: ${DONE} entries."
    if [ "$ERRORS" -gt 0 ]; then
      echo "Errors: ${ERRORS}." >&2
    fi
    ;;

  *)
    echo "Unknown mode: $MODE. Use --list-dirs, --list-dotfiles, or --clone." >&2
    exit 1
    ;;
esac
