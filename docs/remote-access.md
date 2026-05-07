# Remote Access

Guide for accessing persistent worktree sessions from a phone or another device over SSH.

## Prerequisites

- `worktree` script with `--persistent` flag
- [tmux](https://github.com/tmux/tmux) (`brew install tmux`)
- [Tailscale](https://tailscale.com/) on both your Mac and phone
- A mobile SSH client (see below)

## Setup

### 1. Tailscale (private mesh VPN)

Tailscale creates an encrypted private network between your devices. No port forwarding, no dynamic DNS, no firewall rules. Works through NAT, hotel WiFi, and cellular networks.

1. Install Tailscale on your Mac: `brew install --cask tailscale` (or from the [Mac App Store](https://apps.apple.com/app/tailscale/id1475387142))
2. Install Tailscale on your phone:
   - **iOS:** [App Store](https://apps.apple.com/app/tailscale/id1470499037)
   - **Android:** [Play Store](https://play.google.com/store/apps/details?id=com.tailscale.ipn)
3. Sign in on both devices with the same account
4. Note your Mac's Tailscale IP (shown in the Tailscale menu bar app, e.g. `100.x.y.z`)

### 2. SSH on macOS

Enable Remote Login so your Mac accepts SSH connections:

1. Open **System Settings > General > Sharing**
2. Enable **Remote Login**
3. Verify it works locally: `ssh $(whoami)@localhost`

SSH traffic over Tailscale is already encrypted end-to-end. Your Mac's SSH port is only accessible to devices on your tailnet (not the public internet).

### 3. Mobile SSH client

**iOS:**
- [Termius](https://apps.apple.com/app/termius-terminal-ssh-client/id549039908) — best overall UX, good keyboard support
- [Secure ShellFish](https://apps.apple.com/app/secure-shellfish/id1336634154) — built-in tmux integration, iOS Handoff support

**Android:**
- [Termux](https://f-droid.org/packages/com.termux/) with OpenSSH — the most powerful option, gives you a full Linux environment. Install OpenSSH with `pkg install openssh`, then use `ssh` as normal.
- [ConnectBot](https://play.google.com/store/apps/details?id=org.connectbot) — lightweight, open-source, reliable SSH client

### 4. Connect from your phone

1. Open your SSH client
2. Connect to `<your-username>@<tailscale-ip>` (e.g. `mturley@100.64.1.2`)
3. For key-based auth (recommended): generate a key pair in your SSH client and add the public key to `~/.ssh/authorized_keys` on your Mac

## Workflow

```bash
# On your Mac (or from phone via SSH):
worktree -P 1234                    # start a persistent session

# Work with mprocs as usual...
# Press Ctrl+b d to detach (session keeps running)

# Later, from your phone:
ssh mturley@100.64.1.2
worktree -P 1234                    # reattach to the same session

# Or attach directly:
tmux attach -t wt-PR-1234

# List all persistent sessions:
worktree --sessions
```

## Phone usage tips

**Screen space:**
- Use **landscape mode** for more columns
- Press `z` in mprocs to **zoom** the terminal to full screen (hides the process list sidebar)
- Press `z` again to unzoom and see the sidebar
- Use `Ctrl+a` to switch between processes while zoomed
- Increase or decrease font size in your SSH client as needed

**Connection resilience:**
- Tailscale handles most network transitions (WiFi to cellular, etc.)
- If your SSH connection drops, the tmux session keeps running — just reconnect and reattach
- For extra resilience, consider [mosh](https://mosh.org/) (`brew install mosh` on Mac, available in Termux on Android). Mosh handles sleep/wake, network switches, and high-latency connections better than SSH.

**Text input:**
- Consider a voice-to-text tool for longer commands (e.g. [Wispr Flow](https://www.wispr.ai/) on iOS)
- A Bluetooth keyboard makes extended sessions much more comfortable
- Most mobile SSH clients support custom key mappings for `Ctrl`, `Esc`, etc.

## Troubleshooting

**Can't connect via SSH:**
- Verify both devices are on Tailscale: check the Tailscale app on each device
- Verify Remote Login is enabled on your Mac
- Try pinging the Tailscale IP from your phone: some SSH clients have a built-in ping tool
- Check that your firewall allows SSH (port 22) — Tailscale traffic should bypass most firewalls, but macOS's built-in firewall may need an exception

**Session not found on reattach:**
- Run `worktree --sessions` to see active sessions
- The session name is derived from arguments — use the same arguments you used to create it
- If mprocs exited (e.g. all processes were stopped), the tmux session and temp files are cleaned up automatically
