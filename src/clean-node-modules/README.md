# clean-node-modules

Recursively find and delete `node_modules` folders. Scans a directory for `node_modules` folders, lists them with their sizes, asks for confirmation, then deletes them all with verbose output. Handy for reclaiming disk space across many projects at once.

## Prerequisites

- `bash`, `find`, `du`, `rm` (all standard on macOS)

## Usage

```bash
clean-node-modules            # scan the current directory
clean-node-modules ~/git      # scan a specific directory
clean-node-modules --help     # show usage help
```

## Behavior

- Scans `DIR` (default: current directory) recursively for directories named `node_modules`.
- Uses `find ... -prune`, so a `node_modules` nested inside another `node_modules` is not listed separately — the parent's deletion removes it anyway.
- Lists each found folder with its size (`du -sh`) and a total count.
- Prompts once to delete them all. The prompt defaults to **No**; only `y`/`yes` proceeds. Anything else aborts without deleting.
- On confirmation, deletes each folder with `rm -rfv` (verbose per-file output).

## Output

```
Found 2 node_modules folder(s) in .:

  120M	./proj-a/node_modules
  87M	./proj-b/node_modules

Delete all 2 node_modules folder(s)? [y/N] y

./proj-a/node_modules/...
./proj-b/node_modules/...

Done. Deleted 2 node_modules folder(s).
```

If none are found:

```
No node_modules folders found in: .
```
