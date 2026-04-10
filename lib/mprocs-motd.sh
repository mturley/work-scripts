#!/usr/bin/env bash
# mprocs-motd.sh - Print a short mprocs keybinding cheat sheet
# Called from shell panes launched by worktree, odh-dev, etc.

dim="$(tput dim 2>/dev/null || true)"
bold="$(tput bold 2>/dev/null || true)"
reset="$(tput sgr0 2>/dev/null || true)"

cat <<EOF
${bold}mprocs keybindings${reset}
${dim}Ctrl+a${reset}  Toggle focus between process list and terminal
${dim}You can also click with the mouse to change focus.${reset}
${bold}When focused on the process list:${reset}
  ${dim}arrows${reset}  Navigate processes
  ${dim}r${reset}       Restart selected process
  ${dim}x${reset}       Stop selected process
  ${dim}X${reset}       Force-stop selected process
  ${dim}q${reset}       Quit (asks to stop running processes)
  ${dim}Q${reset}       Force-quit all processes and exit
${dim}This shell pane must be exited or force-quit (Q) to close mprocs.${reset}
EOF
