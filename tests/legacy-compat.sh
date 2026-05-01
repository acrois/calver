#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CALVER="$ROOT_DIR/calver"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_match() {
    local value="$1"
    local pattern="$2"
    local msg="$3"
    if ! [[ "$value" =~ $pattern ]]; then
        fail "$msg (value=$value pattern=$pattern)"
    fi
}

new_repo() {
    local dir
    dir="$(mktemp -d)"
    git init -b main "$dir" >/dev/null
    (
        cd "$dir"
        git config user.name "test"
        git config user.email "test@example.com"
        git config tag.gpgSign false
        git config commit.gpgSign false
    )
    echo "$dir"
}

create_commit() {
    local repo="$1"
    local ts="$2"
    local content="$3"
    (
        cd "$repo"
        printf '%s\n' "$content" >> app.txt
        git add app.txt
        GIT_AUTHOR_DATE="$ts" GIT_COMMITTER_DATE="$ts" git commit -m "$content" >/dev/null
    )
}

test_legacy_auto_dry_run() {
    local repo out
    repo="$(new_repo)"
    create_commit "$repo" "2026-04-24T10:00:00Z" "legacy-auto"
    out="$(
        cd "$repo"
        "$CALVER" --auto
    )"
    assert_match "$out" 'DRY RUN - NOTHING WILL BE CHANGED' "legacy --auto should remain dry-run by default"
    rm -rf "$repo"
}

test_legacy_auto_apply_tags() {
    local repo tag has_base=false has_revision=false
    repo="$(new_repo)"
    create_commit "$repo" "2026-04-24T10:00:00Z" "legacy-apply"
    (
        cd "$repo"
        "$CALVER" --auto --apply >/dev/null
        while IFS= read -r tag; do
            [[ "$tag" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}$ ]] && has_base=true
            [[ "$tag" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[0-9]+$ ]] && has_revision=true
        done < <(git tag -l)

        [ "$has_base" = true ] || fail "legacy --auto --apply should create base calendar tag"
        [ "$has_revision" = true ] || fail "legacy --auto --apply should create revision tag"
    )
    rm -rf "$repo"
}

test_legacy_date_show_revision() {
    local repo out expected_base
    repo="$(new_repo)"
    create_commit "$repo" "2026-04-24T10:00:00Z" "legacy-date"
    expected_base="$(TZ=UTC printf "%s.%02d" "$(date +%Y.%V -d "2026-04-24T00:00:00Z")" "$(date +%u -d "2026-04-24T00:00:00Z")")"
    out="$(
        cd "$repo"
        "$CALVER" --date=2026-04-24T00:00:00Z --show=revision
    )"
    assert_match "$out" "^$expected_base(\\.[0-9]+)?$" "legacy --date --show=revision should still work"
    rm -rf "$repo"
}

test_legacy_version_show_revision() {
    local repo out
    repo="$(new_repo)"
    create_commit "$repo" "2026-04-24T10:00:00Z" "legacy-version"
    out="$(
        cd "$repo"
        "$CALVER" --version=2030.01.01 --show=revision
    )"
    assert_match "$out" '^2030\.01\.01(\.[0-9]+)?$' "legacy --version --show=revision should still work"
    rm -rf "$repo"
}

main() {
    test_legacy_auto_dry_run
    test_legacy_auto_apply_tags
    test_legacy_date_show_revision
    test_legacy_version_show_revision
    echo "Legacy compatibility checks passed."
}

main "$@"
