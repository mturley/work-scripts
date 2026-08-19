#!/usr/bin/env bash
# cmux-open-next-pane - Open a file/URL in the pane AFTER the current one, or split if last.
# Usage: cmux-open-next-pane <file-or-url> [extra cmux args...]
#
# cmux's `markdown open` (and browser opens) always create a NEW split, so
# opening several files scatters them into many splits. This wrapper instead
# collects opened files into the pane immediately to the right of the focused
# one, only splitting when there is no pane to the right.
#
# "Pane" here means a split (a layout region); "surface" means a tab within a
# pane. `cmux list-panes` lists panes in layout order and marks the focused one.
#
# Behavior:
#   - Focused pane is NOT the last pane:
#       cmux open <target> --pane <next-pane> --no-focus
#     Adds the file/URL as a tab in the next pane (markdown keeps its rich
#     live-reload viewer). Works uniformly for markdown, other files, and URLs.
#   - Focused pane IS the last pane (need a new split). The command differs by
#     type because that is what yields a clean split (no stray terminal tab):
#       *.md   -> cmux markdown open <target> --focus false   (clean split, viewer)
#       URL    -> cmux open <target> --no-focus               (clean browser split)
#       other  -> cmux open <target> --no-focus               (adds a tab; no
#                                                              stray-free split exists)
#
# In every case the target opens without stealing focus.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: cmux-open-next-pane <file-or-url> [extra cmux args...]

Open a file or URL in the cmux pane after the current one, collecting opened
files there instead of scattering them into new splits. If the current pane is
the last pane, a clean new split is created instead.

Arguments:
  <file-or-url>   Path or URL to open.
  [extra args]    Additional flags forwarded to the underlying cmux command
                  (e.g. --workspace).

Behavior:
  - Not the last pane -> opens as a tab in the next pane (cmux open --pane).
  - Last pane, *.md   -> cmux markdown open (clean split, rich viewer).
  - Last pane, URL    -> cmux open (clean browser split).
  - Last pane, other  -> cmux open (adds a tab in the current pane).
  - Always opens without stealing focus.

Requires running inside cmux (CMUX_WORKSPACE_ID set) with `cmux` on PATH.
EOF
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  "")
    echo "cmux-open-next-pane: missing <file-or-url> argument." >&2
    echo "" >&2
    usage >&2
    exit 1
    ;;
esac

TARGET="$1"
shift

if ! command -v cmux >/dev/null 2>&1; then
  echo "cmux-open-next-pane: 'cmux' not found on PATH." >&2
  exit 1
fi

if [[ -z "${CMUX_WORKSPACE_ID:-}" ]]; then
  echo "cmux-open-next-pane: not running inside cmux (CMUX_WORKSPACE_ID unset)." >&2
  exit 1
fi

# Classify the target so the last-pane case can pick the cleanest split command.
is_url() {
  case "$1" in
    http://*|https://*) return 0 ;;
    *) return 1 ;;
  esac
}
is_markdown() {
  case "$1" in
    *.md|*.markdown) return 0 ;;
    *) return 1 ;;
  esac
}

# Find the ref of the pane after the focused one, in layout order.
# list-panes prints one pane per line, e.g.:
#     * pane:4  [3 surfaces]  [focused]
#       pane:5  [2 surfaces]
# The focused pane is marked with a leading "*" and/or "[focused]". The pane:N
# tokens are stable refs; we target by ref because `cmux open --pane` does not
# resolve bare positional indexes reliably.
NEXT_PANE="$(cmux list-panes 2>/dev/null | awk '
  {
    focused = ($0 ~ /\[focused\]/ || $1 == "*")
    ref = ""
    for (i = 1; i <= NF; i++) if ($i ~ /^pane:/) ref = $i
    if (ref != "") {
      n++
      refs[n] = ref
      if (focused) focus_idx = n
    }
  }
  END {
    # Print the next pane ref only when the focused pane is not the last one.
    if (focus_idx != "" && focus_idx < n) print refs[focus_idx + 1]
  }
')"

if [[ -n "$NEXT_PANE" ]]; then
  # Not the last pane: add the target as a tab in the next pane. This path is
  # uniform across markdown, other files, and URLs.
  exec cmux open "$TARGET" --pane "$NEXT_PANE" --no-focus "$@"
fi

# Last pane (or focus couldn't be determined): create a clean split by type.
if is_markdown "$TARGET"; then
  exec cmux markdown open "$TARGET" --focus false "$@"
else
  # URLs open as a clean browser split; other files fall back to a tab in the
  # current pane (cmux has no stray-terminal-free split for arbitrary files).
  exec cmux open "$TARGET" --no-focus "$@"
fi
