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
  ${dim}z${reset}       Zoom terminal to full screen (press again to unzoom)
  ${dim}r${reset}       Restart selected process
  ${dim}x${reset}       Stop selected process
  ${dim}X${reset}       Force-stop selected process
  ${dim}d${reset}       Remove selected process from the list
  ${dim}q${reset}       Quit (asks to stop running processes)
  ${dim}Q${reset}       Force-quit all processes and exit
${dim}This shell pane must be exited or force-quit (Q) to close mprocs.${reset}
EOF

if [ -n "${TMUX:-}" ]; then
  cat <<EOF

${bold}tmux persistence${reset}
${dim}Ctrl+b d${reset}  Detach (session keeps running in the background)
${dim}Quitting mprocs (q/Q) will automatically exit tmux.${reset}
${dim}Reattach with: worktree <same args>${reset}
${dim}List sessions: worktree --sessions${reset}

${bold}mobile tips${reset}
${dim}z${reset}          Zoom terminal to full screen (hide sidebar for narrow screens)
${dim}Ctrl+a${reset}     Switch between processes while zoomed
EOF
fi
