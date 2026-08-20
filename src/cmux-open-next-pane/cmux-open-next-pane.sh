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
#   0. Already open: if a file surface in the current workspace is already
#      showing this file (matched by basename), don't open a duplicate.
#      - If this workspace is the one currently in focus (its window is the key
#        window and this workspace is its selected workspace), switch that pane
#        to the existing tab, then restore focus to the pane we came from — so
#        the tab is surfaced without leaving the focused pane changed.
#      - Otherwise (running in a background workspace) do nothing at all, so a
#        file written by a background agent never yanks focus to its workspace.
#      (File targets only; needs `jq`.)
#   1. Focused pane is NOT the last pane:
#        cmux open <target> --pane <next-pane> --no-focus
#      Adds the file/URL as a tab in the next pane (markdown keeps its rich
#      live-reload viewer). Works uniformly for markdown, other files, and URLs.
#   2. Focused pane IS the last pane (need a new split). The command differs by
#      type because that is what yields a clean split (no stray terminal tab):
#        *.md   -> cmux markdown open <target> --focus false  (clean split, viewer)
#        URL    -> cmux open <target> --no-focus              (clean browser split)
#        other  -> cmux open <target> --no-focus              (adds a tab; no
#                                                             stray-free split exists)
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
  - Already open  -> no duplicate. If this workspace is focused, switches to the
                     existing tab and restores focus to the origin pane;
                     otherwise (background workspace) does nothing.
  - Not the last pane -> opens as a tab in the next pane (cmux open --pane).
  - Last pane, *.md   -> cmux markdown open (clean split, rich viewer).
  - Last pane, URL    -> cmux open (clean browser split).
  - Last pane, other  -> cmux open (adds a tab in the current pane).
  - Never steals focus.

Requires running inside cmux (CMUX_WORKSPACE_ID set) with `cmux` on PATH.
The already-open check additionally requires `jq`; without it that step is
skipped and the file opens normally.
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

# Step 0: if the file is already open in this workspace, do nothing.
#
# `cmux rpc surface.list` reports each surface's type and title, but a file
# surface's title is only the file's *basename* (no full path), so matching is
# by basename against markdown/filepreview surfaces. Skipped for URLs (their
# titles are hostnames, not reliable) and when `jq` is unavailable. This keeps
# repeated opens (e.g. an editor hook firing on every save) from piling up
# duplicate tabs; the existing tab is left as-is and focus is not stolen.
if ! is_url "$TARGET" && command -v jq >/dev/null 2>&1; then
  BASENAME="${TARGET##*/}"
  EXISTING_SURFACE="$(
    cmux rpc surface.list "{\"workspace_id\":\"$CMUX_WORKSPACE_ID\"}" 2>/dev/null \
      | jq -r --arg b "$BASENAME" '
          [ .surfaces[]
            | select((.type == "markdown" or .type == "filepreview") and .title == $b)
            | .ref
          ] | first // empty
        ' 2>/dev/null || true
  )"
  if [[ -n "$EXISTING_SURFACE" ]]; then
    # Already open — don't duplicate. Only surface the existing tab when this
    # workspace is the one in focus; otherwise leave it untouched so a
    # background write never pulls focus to this workspace.
    WS_FOCUSED="$(
      cmux rpc window.list '{}' 2>/dev/null \
        | jq -r --arg ws "$CMUX_WORKSPACE_ID" '
            any(.windows[]; .key == true and .selected_workspace_id == $ws)
          ' 2>/dev/null || true
    )"
    if [[ "$WS_FOCUSED" == "true" ]]; then
      # Remember the pane we're in so we can hand focus back after switching.
      ORIGIN_PANE="$(
        cmux rpc surface.list "{\"workspace_id\":\"$CMUX_WORKSPACE_ID\"}" 2>/dev/null \
          | jq -r '.surfaces[] | select(.focused == true) | .pane_ref' 2>/dev/null \
          | head -n 1 || true
      )"
      # Switch the existing tab's pane to it, then restore focus to the origin.
      cmux move-surface --surface "$EXISTING_SURFACE" --focus true >/dev/null 2>&1 || true
      if [[ -n "$ORIGIN_PANE" ]]; then
        cmux focus-pane --pane "$ORIGIN_PANE" >/dev/null 2>&1 || true
      fi
    fi
    exit 0
  fi
fi

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
