# mprocs-new

Add panes to an existing mprocs session or start a new mprocs with the specified commands.

## Prerequisites

- **mprocs** - Install with `brew install mprocs`

## Usage

```bash
mprocs-new <command> [label]
mprocs-new <command1> <command2> ...
```

### Arguments

- `<command>` - Shell command to run in the new pane
- `<label>` - Optional label for the pane (defaults to the command itself)

### Behavior

- **Inside mprocs** (`MPROCS_SOCKET` is set): Adds pane(s) to the current session and switches to the newly added pane if only one was added
- **Outside mprocs**: Starts a new mprocs with a shell pane and the specified command pane(s)

## Examples

### Add a single pane with custom label

```bash
mprocs-new "npm run dev" "dev server"
```

### Add a single pane with default label

```bash
mprocs-new "npm test"
```

The pane label will be "npm test".

### Add multiple panes at once

```bash
mprocs-new "npm run dev" "npm test" "npm run lint"
```

Creates three new panes (or starts a new mprocs with a shell + three command panes).

### Start a new mprocs session

When not already inside mprocs:

```bash
mprocs-new "npm run dev"
```

This creates a new mprocs session with:
- A shell pane (labeled `[bash]` or `[zsh]`)
- A command pane running `npm run dev`

## Environment Variables

- `MPROCS_SOCKET` - Set by mprocs when running inside a session. Used to detect whether to add panes or start a new session.

## How It Works

The script detects whether it's running inside an mprocs session by checking for the `MPROCS_SOCKET` environment variable.

**Inside mprocs:**
- Uses `mprocs --server $MPROCS_SOCKET --ctl` to add panes dynamically
- Tracks the proc count to enable automatic focus switching for single-pane additions
- If only one pane is added, switches to it after a brief delay

**Outside mprocs:**
- Generates a temporary YAML config with a shell pane and the requested command panes
- Starts mprocs with `--config` and `--server` flags
- Sets `MPROCS_SOCKET` in all panes so future `mprocs-new` calls within that session add panes instead of starting new sessions
