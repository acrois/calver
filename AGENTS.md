# AGENTS.md

## Cursor Cloud specific instructions

This repo is a single self-contained Bash CLI, `calver` (with a `calver.sh` symlink pointing at
the same file), that tags git commits using [CalVer](https://calver.org/). There is no package
manager, build step, test suite, or linter — the "application" is the script itself.

- Dependencies are all standard system tools already present on the VM: `bash`, `git`, `awk`
  (`mawk`), and GNU `coreutils` `date`. Nothing needs to be installed; the update script is a
  no-op safety net that only ensures the script stays executable.
- Run it directly from the repo root: `./calver --help` (note: `--help`/usage exits with code `1`
  by design, not `0`).
- Safe to run: without `--apply` it is a dry run and changes nothing. `--apply` creates local git
  tags; `--push` additionally force-pushes tags to `origin` — only use `--push` intentionally.
- To exercise real tag creation without touching this repo's tags, run against a throwaway repo,
  e.g. `git init` a temp dir, make an empty commit, then run `/workspace/calver --apply ...`.
- Useful non-mutating checks: `./calver --auto` (dry-run version for the current branch) and
  `./calver --show=revision --date=2023-05-10 --variant=dev` (prints just the computed tag).
