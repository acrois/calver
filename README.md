# calver

[Build Image](https://github.com/acrois/scripts/actions/workflows/build.yaml)

Give each commit in your repo a version.

`[calver](./calver)` - Utility for automatically tagging git repositories using [CalVer](https://calver.org/).

## GitHub Actions Usage

GitHub Action enabling [CalVer](https://calver.org/) tagging.

Example of usage in [GitHub Actions Workflow](https://github.com/acrois/scripts/actions/workflows/calver.yaml):

```yaml
name: CalVer Tagging
on:
  push:
    branches:
      - "**"
    tags-ignore:
      - "**"
permissions:
  contents: write
concurrency: tag-scripts
jobs:
  apply:
    runs-on: ubuntu-latest
    name: Tag revision
    steps:
      - name: Checkout
        uses: actions/checkout@v6
        with:
          fetch-depth: 0
          fetch-tags: true
      - name: Version
        uses: acrois/calver@trunk
```

### Action Inputs

Defaults are intentionally backwards compatible with `origin/trunk`, so calling the action with no inputs behaves like:

```sh
calver --auto --apply --push
```


| Input               | Default       | Notes                                                               |
| ------------------- | ------------- | ------------------------------------------------------------------- |
| `version`           | `""`          | Explicit calendar version to release                                |
| `prefix`            | `""`          | Prefix prepended to generated tags                                  |
| `format`            | `""`          | Custom date format                                                  |
| `date`              | `""`          | Date to base version on                                             |
| `revision`          | `""`          | Explicit revision override                                          |
| `variant`           | `""`          | Explicit variant override                                           |
| `auto`              | `"true"`      | Enable branch-based variant auto-selection                          |
| `backfill`          | `"false"`     | Backfill recent untagged commits                                    |
| `backfill-days`     | `""`          | Days to backfill from HEAD commit timestamp                         |
| `backfill-all`      | `"false"`     | Backfill full reachable history                                     |
| `backfill-base-ref` | `"__unset__"` | Limit backfill to merge-base range; only passed when explicitly set |
| `clear-branch-tags` | `"false"`     | Clear tags in the selected backfill range first                     |
| `apply`             | `"true"`      | Disable dry-run and apply tags                                      |
| `push`              | `"true"`      | Push tags to origin                                                 |
| `show`              | `""`          | Show one value and exit (`calendar`, `variant`, `revision`)         |
| `verbose`           | `"false"`     | Enable shell trace mode (`--v`)                                     |
| `help`              | `"false"`     | Print CLI help and exit                                             |


### Adopting Or Updating Existing Repositories

The action normally pushes tags with the workflow's default `GITHUB_TOKEN`; no checkout token or extra credentials are needed for the common case. Make sure the workflow grants `contents: write`, as shown above, so GitHub Actions can create and move tags.

When adopting CalVer into a repository, or updating from an older workflow, first inspect what would change from a local clone with the `calver` utility installed:

```sh
git fetch --all --tags
calver --auto
```

If the dry run looks correct, apply and push the current commit's tags:

```sh
calver --auto --apply --push
```

This brings the repository back in line without backfilling older commits. It tags the current commit and moves the calendar or variant tag for the active stream. On `trunk`, `main`, or `master`, `--auto` emits unqualified calendar tags such as `2026.18.01`.

If an older or failed workflow run left missing tags on the current branch, but you still do not want to backfill older trunk history, use a branch-scoped repair instead:

```sh
calver --auto --backfill-all --backfill-base-ref= --clear-branch-tags
calver --auto --backfill-all --backfill-base-ref= --clear-branch-tags --apply --push
```

The empty `--backfill-base-ref=` tells `calver` to detect the primary branch and limit the repair to commits after the branch point.

If a push fails with an error like:

```text
refusing to allow a GitHub App to create or update workflow `.github/workflows/calver.yaml` without `workflows` permission
```

the token pushing the tag is a GitHub App token that does not have the `workflows` permission, and at least one rejected tag points at a commit that changes a workflow file. Fix it by either running the local reconciliation above with your own authenticated git credentials, granting the GitHub App `workflows` permission, or removing the custom checkout token and using the default `GITHUB_TOKEN` with `contents: write` when app credentials are not required.

Wait for the completion of the workflow (example)

### Build Workflow

Save to `.github/workflows/build.yaml` ([raw](./build.example.yaml))

```yaml
name: Build Solution
on:
  push:
    branches:
      - '**'
    tags:
      - '**'
permissions:
  contents: read
  actions: read
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: false
jobs:
  prepare-execution-matrix:
    runs-on: 'ubuntu-latest'
    steps:
      - name: Watch CalVer Workflow
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          WATCH_WORKFLOW: calver.yaml
        run: |
          RUN_ID=$(gh run list --workflow "$WATCH_WORKFLOW" --repo="${{ github.repository }}" --commit ${{ github.sha }} --limit 1 --json databaseId --jq '.[0].databaseId')
          gh run watch "$RUN_ID" --repo="${{ github.repository }}" --exit-status
      - name: Checkout Repository
        uses: actions/checkout@v6
        with:
          fetch-depth: 0
          fetch-tags: true
      - name: Prepare Execution Matrix
        id: set-matrix
        run: |
          export TAGS=$(git for-each-ref --format '%(refname:short)' refs/heads/ refs/tags/ | while read ref; do
            REF_SHA=$(git rev-parse "$ref")
            # echo "Checking $ref $REF_SHA"

            if [ "$REF_SHA" = "$GITHUB_SHA" ] && perl -e 'exit (shift =~ /^(\d+)\.(\d+)\.(\d+)(?:-([\w\d_.\/-]+?))?(?:\.(\d+))*?$/ ? 0 : 1)' "$ref"; then
              echo "$ref" | tr '/' '-'
              # echo "MATCH: $ref"
            fi
          done | jq -R -s -c 'split("\n")[:-1]')
          [ -n "$TAGS" ] || TAGS='[]'
          echo "MATRIX=$TAGS" >> $GITHUB_OUTPUT
    outputs:
      matrix: ${{ steps.set-matrix.outputs.MATRIX }}
  execute-scripts:
    needs: prepare-execution-matrix
    runs-on: 'ubuntu-latest'
    strategy:
      fail-fast: false
      matrix:
        version: ${{ fromJson(needs.prepare-execution-matrix.outputs.matrix) }}
    name: Build and Release
    concurrency:
      group: ${{ github.workflow }}-${{ github.ref }}-${{ matrix.version }}
      cancel-in-progress: true
    steps:
      - name: Checkout
        uses: actions/checkout@v6
        with:
          fetch-depth: 0
          submodules: true
      - name: Build and Release
        run: |
          echo "Building and releasing version ${{ matrix.version }}"
          # Add your build and release commands here, for example:
          # ./build.sh --version ${{ matrix.version }}
          # ./release.sh --version ${{ matrix.version }}
```



## Docker Usage

```sh
docker run --rm -v "$PWD:/run" ghcr.io/acrois/scripts calver --help
```

## CLI Install

Simply run the following:

```sh
sudo curl -o /usr/local/bin/calver https://raw.githubusercontent.com/acrois/calver/HEAD/calver
sudo chmod +x /usr/local/bin/calver
```

## CLI Usage

```
Usage:
        calver --version="2023.19.03" --variant="dev" --revision="10"
        calver --date="2023-05-10" --variant="dev" --revision="10"

Output tags:
        Revision:  2023.19.03-dev.10
        Variant:   2023.19.03-dev
        Calendar:  2023.19.03

Flags:
        --format            - date format, defaults to %Y.%V.%u according to `man date`
        --version           - version to release
        --date              - date to base version off of
        --auto              - automatically creates variants based on branch name.
                                if on main, master, or trunk it is "".
                                if there is no branch, it is "detached".
        --variant           - adds a variant tag e.g
        --revision          - adds a revision incrementer after the variant e.g 2023.19.03-dev.10
        --prefix            - adds a prefix in front of the version e.g node/2023.19.03-dev.10
        --backfill          - tags untagged commits from at least one day before HEAD
        --backfill-days     - days to backfill from HEAD commit timestamp (default: 1)
        --backfill-all      - backfills tags for the entire reachable history from HEAD
        --backfill-base-ref - limit backfill to commits after merge-base with this ref (empty: auto primary)
        --clear-branch-tags - clear tags that point at commits in the backfill range
        --apply             - disable dry run and do it for real
        --push              - push after applying
        --show              - show version tag (values: calendar, variant, revision)
        --v                 - verbose output (`set -x`)
        --help              - prints this useful information
```

## Compatibility And Rollout

- Existing command forms remain supported; newer behavior is opt-in via backfill flags.
- Legacy-safe invocations such as `--auto`, `--auto --apply`, `--date=... --show=revision`, and `--version=... --show=revision` are covered by `tests/legacy-compat.sh`.
- Full regression coverage (including legacy checks) runs via `tests/run.sh`.
- For production rollout, run without `--apply --push` first to inspect output, then rerun with apply/push enabled.
- For one-time branch-only bootstrap, prefer `--backfill-all --backfill-base-ref= --clear-branch-tags` to avoid touching older trunk history.

