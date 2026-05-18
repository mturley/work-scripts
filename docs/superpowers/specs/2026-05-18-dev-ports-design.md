# dev-ports Design Spec

## Purpose

Find all listening TCP ports whose process is running in a git repository, and display them grouped by repo and branch/worktree. Helps navigate back to running dev servers across a mess of terminals and worktrees.

## v1 Scope

Bare command, no arguments or flags. Future versions will add `--verbose`, `--parents`, and `--repo <path>`.

## Data Collection Pipeline

1. **Get all TCP listeners:** `lsof -iTCP -sTCP:LISTEN -nP` — one call, returns PID, port, and process name for every listening socket.
2. **Get working directory per PID:** `lsof -a -p <pid> -d cwd -Fn` — returns the cwd of the process.
3. **Check if cwd is in a git repo:** `git -C <cwd> rev-parse --show-toplevel` — if this fails, discard the PID.
4. **Get repo identity:** `git -C <cwd> rev-parse --path-format=absolute --git-common-dir` — resolves the real repo root (not the worktree), so worktrees group under their parent repo.
5. **Get branch name:** `git -C <cwd> branch --show-current` — empty result means detached HEAD.
6. **Get process command:** `ps -ww -o args= -p <pid>` — full command line (e.g. `webpack`, `node ./server.js`). Truncated to 40 characters in default output.

## Grouping & Sorting

- Group by **repo root** (from `--git-common-dir`, stripping the trailing `/.git`).
- Within each repo, group by **worktree path** (from `--show-toplevel`) + **branch**.
- Repos sorted alphabetically by name (basename of repo root).
- Branches within a repo sorted alphabetically.
- Ports within a branch sorted numerically.

## Output Format

```
<repo-basename> (<repo-root-with-tilde>)
  <branch> (<worktree-path-with-tilde>)
    :<port>  <command-truncated> (pid <pid>)
```

- Repo root path has `$HOME` replaced with `~`.
- Worktree path in parentheses is shown only when the worktree path differs from the repo root (i.e. it's an actual worktree, not the main checkout).
- Detached HEAD is shown as `(detached)`.
- Command is truncated to 40 characters for readability.

### Example

```
odh-dashboard (~/git/rhoai-work/opendatahub-io/odh-dashboard)
  main
    :3000  webpack (pid 45678)
  RHOAIENG-60274 (~/git/.worktrees/odh-dashboard/pr-7433-feat-nim-serving-add-nimservice-watch-de)
    :4031  webpack (pid 32103)
```

### No Results

```
No dev servers found in git repositories.
```

## Edge Cases

- **Detached HEAD:** `git branch --show-current` returns empty. Display `(detached)` as the branch name.
- **Process disappears between lsof calls:** Silently skip — processes are ephemeral.
- **Permission errors from lsof:** Should not occur (only inspecting own user's processes). Skip silently if so.
- **Multiple ports on same PID:** Each port gets its own line under the same branch grouping.
- **Same port on IPv4 and IPv6:** Show both (they're separate listeners).

## Constraints

- Bash 3.2 compatible (macOS). No associative arrays, no `mapfile`, no `readarray`.
- POSIX-compatible external tools only (lsof, ps, git, sort — all ship with macOS).
- No arguments or flags in v1.

## Future Versions (planned, not in v1)

1. **`--verbose` / `-v`:** Full untruncated command line.
2. **`--parents`:** Walk parent PID chain to find a git repo if the direct listener's cwd is not in one. Flag inferred results in output (e.g. `(via parent)`).
3. **`--repo <path>`:** Filter output to a specific repo. Supports relative paths (e.g. `--repo .` resolves to the repo containing the current directory).
