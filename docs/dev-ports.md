# dev-ports

Find dev servers running in git repositories. Lists all listening TCP ports whose process working directory is inside a git repo, grouped by repository and branch/worktree.

## Prerequisites

- macOS (uses `lsof` for process/port discovery)
- `git`

## Usage

```bash
dev-ports
```

No arguments or flags. Scans all listening TCP ports and filters to those running in git repos.

## Output

Listeners are grouped by repository, then by branch/worktree, with ports listed under each:

```
odh-dashboard (~/git/rhoai-work/opendatahub-io/odh-dashboard)
  main
    :3000  webpack (pid 45678)
  RHOAIENG-60274 (~/git/.worktrees/odh-dashboard/RHOAIENG-60274)
    :4031  node ~/git/.worktr...node src/server.ts (pid 32103)
    :4032  webpack (pid 32104)

model-registry (~/git/model-registry)
  feature-branch (~/git/.worktrees/model-registry/feature-branch)
    :8080  python3 manage.py runserver (pid 34567)
```

- Repository name is the directory basename, with the full path in parentheses.
- Worktree path is shown only when the listener is running in a worktree (not the main checkout).
- Home directory paths (`/Users/you/...`) are replaced with `~` everywhere in the output.
- Long process commands are truncated in the middle so both the beginning and end are visible.
- Detached HEAD is shown as `(detached)`.

If no dev servers are found in any git repository:

```
No dev servers found in git repositories.
```
