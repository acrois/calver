# calver

Give each commit in your repo a version.

[calver.sh](./calver.sh) - Utility for automatically tagging git repositories using [CalVer](https://calver.org/).

## GitHub Actions Usage

GitHub Action enabling [CalVer](https://calver.org/) tagging.

Example of usage in GitHub Actions Workflow:

```yaml
name: CalVer Tagging
on:
  push:
    branches:
      - "**"
    tags:
      - "!**"
concurrency: tag-scripts
jobs:
  apply:
    runs-on: ubuntu-latest
    name: Tag revision
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: Version
        uses: acrois/calver@trunk
```

## Docker Usage

## CLI Install

Simply run the following:

```sh
sudo curl -o /usr/local/bin/calver.sh https://raw.githubusercontent.com/acrois/calver/HEAD/calver.sh
sudo chmod +x /usr/local/bin/calver.sh
```

## CLI Usage

[//]: # (using calver.sh)
```
Usage:
        calver.sh --version="2023.19.03" --variant="dev" --revision="10"
        calver.sh --date="2023-05-10" --variant="dev" --revision="10"

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
        --apply             - disable dry run and do it for real
        --push              - push after applying
        --show              - show version tag (values: calendar, variant, revision)
        --v                 - verbose output (`set -x`)
        --help              - prints this useful information
```
[//]: # (used calver.sh)
