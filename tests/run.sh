#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CALVER="$ROOT_DIR/calver"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local msg="$3"
    if [ "$expected" != "$actual" ]; then
        fail "$msg (expected=$expected actual=$actual)"
    fi
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
        git rev-parse HEAD
    )
}

test_git_default_uses_head_timestamp() {
    local repo expected actual head_sha commit_ts
    repo="$(new_repo)"
    head_sha="$(create_commit "$repo" "2026-04-24T23:30:00Z" "first")"

    (
        cd "$repo"
        commit_ts="$(git show -s --format=%cI "$head_sha")"
        expected="$(TZ=UTC printf "%s.%02d" "$(date +%Y.%V -d "$commit_ts")" "$(date +%u -d "$commit_ts")")"
        actual="$(TZ=UTC "$CALVER" --show=calendar)"
        assert_eq "$expected" "$actual" "calendar should derive from HEAD commit time"
    )

    rm -rf "$repo"
}

test_backfill_tags_recent_commits() {
    local repo old_sha new_sha
    repo="$(new_repo)"
    old_sha="$(create_commit "$repo" "2026-04-23T11:00:00Z" "old")"
    new_sha="$(create_commit "$repo" "2026-04-24T12:00:00Z" "new")"

    (
        cd "$repo"
        "$CALVER" --backfill --backfill-days=2 --apply >/dev/null

        old_tags="$(git tag --points-at "$old_sha")"
        new_tags="$(git tag --points-at "$new_sha")"

        assert_match "$old_tags" '[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[0-9]+' "old commit should have revision tag"
        assert_match "$new_tags" '[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[0-9]+' "new commit should have revision tag"
    )

    rm -rf "$repo"
}

test_backfill_rerun_is_stable() {
    local repo first second
    repo="$(new_repo)"
    create_commit "$repo" "2026-04-24T10:00:00Z" "a" >/dev/null
    create_commit "$repo" "2026-04-24T14:00:00Z" "b" >/dev/null

    (
        cd "$repo"
        "$CALVER" --backfill --backfill-days=1 --apply >/dev/null
        first="$(git tag --sort=refname | tr '\n' ' ')"

        "$CALVER" --backfill --backfill-days=1 --apply >/dev/null
        second="$(git tag --sort=refname | tr '\n' ' ')"

        assert_eq "$first" "$second" "tag set should not change on rerun"
    )

    rm -rf "$repo"
}

test_base_tag_tracks_latest_commit() {
    local repo first_sha second_sha base_tag
    repo="$(new_repo)"
    first_sha="$(create_commit "$repo" "2026-04-24T10:00:00Z" "a")"
    second_sha="$(create_commit "$repo" "2026-04-24T14:00:00Z" "b")"

    (
        cd "$repo"
        "$CALVER" --backfill-all --apply >/dev/null
        base_tag="$(git tag -l "2026.17.05")"
        base_tag_sha="$(git rev-list -n 1 "$base_tag")"
        assert_eq "$second_sha" "$base_tag_sha" "base tag should move to latest commit"

        first_rev_sha="$(git rev-list -n 1 "2026.17.05.0")"
        second_rev_sha="$(git rev-list -n 1 "2026.17.05.1")"
        assert_eq "$first_sha" "$first_rev_sha" "revision .0 should stay on first commit"
        assert_eq "$second_sha" "$second_rev_sha" "revision .1 should point to second commit"
    )

    rm -rf "$repo"
}

test_default_base_tag_tracks_latest_commit() {
    local repo first_sha second_sha base_tag base_tag_sha first_rev_sha second_rev_sha
    repo="$(new_repo)"
    first_sha="$(create_commit "$repo" "2026-04-24T10:00:00Z" "a")"

    (
        cd "$repo"
        "$CALVER" --apply >/dev/null
        base_tag="$(git tag -l "2026.17.05")"
        base_tag_sha="$(git rev-list -n 1 "$base_tag")"
        assert_eq "$first_sha" "$base_tag_sha" "base tag should initially point at first commit"
    )

    second_sha="$(create_commit "$repo" "2026-04-24T14:00:00Z" "b")"

    (
        cd "$repo"
        "$CALVER" --apply >/dev/null
        base_tag="$(git tag -l "2026.17.05")"
        base_tag_sha="$(git rev-list -n 1 "$base_tag")"
        assert_eq "$second_sha" "$base_tag_sha" "default base tag should move to latest same-day commit"

        first_rev_sha="$(git rev-list -n 1 "2026.17.05.0")"
        second_rev_sha="$(git rev-list -n 1 "2026.17.05.1")"
        assert_eq "$first_sha" "$first_rev_sha" "default revision .0 should stay on first commit"
        assert_eq "$second_sha" "$second_rev_sha" "default revision .1 should point to second commit"
    )

    rm -rf "$repo"
}

test_backfill_all_tags_entire_history() {
    local repo first_sha second_sha third_sha
    repo="$(new_repo)"
    first_sha="$(create_commit "$repo" "2026-04-20T09:00:00Z" "one")"
    second_sha="$(create_commit "$repo" "2026-04-21T09:00:00Z" "two")"
    third_sha="$(create_commit "$repo" "2026-04-24T09:00:00Z" "three")"

    (
        cd "$repo"
        "$CALVER" --backfill-all --apply >/dev/null

        first_tags="$(git tag --points-at "$first_sha")"
        second_tags="$(git tag --points-at "$second_sha")"
        third_tags="$(git tag --points-at "$third_sha")"

        assert_match "$first_tags" '[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[0-9]+' "first commit should have revision tag"
        assert_match "$second_tags" '[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[0-9]+' "second commit should have revision tag"
        assert_match "$third_tags" '[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[0-9]+' "third commit should have revision tag"
    )

    rm -rf "$repo"
}

test_backfill_pushes_tags_once() {
    local repo git_wrapper_dir push_log real_git push_count push_command
    repo="$(new_repo)"
    create_commit "$repo" "2026-04-20T09:00:00Z" "one" >/dev/null
    create_commit "$repo" "2026-04-21T09:00:00Z" "two" >/dev/null
    create_commit "$repo" "2026-04-24T09:00:00Z" "three" >/dev/null
    git_wrapper_dir="$(mktemp -d)"
    push_log="$git_wrapper_dir/push.log"
    real_git="$(command -v git)"

    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -euo pipefail' \
        'if [ "${1:-}" = push ]; then' \
        '    printf "%s\n" "$*" >> "$PUSH_LOG"' \
        '    exit 0' \
        'fi' \
        'exec "$REAL_GIT" "$@"' > "$git_wrapper_dir/git"
    chmod +x "$git_wrapper_dir/git"

    (
        cd "$repo"
        PATH="$git_wrapper_dir:$PATH" REAL_GIT="$real_git" PUSH_LOG="$push_log" "$CALVER" --backfill-all --apply --push >/dev/null
    )

    push_count="$(wc -l < "$push_log" | tr -d ' ')"
    assert_eq "1" "$push_count" "backfill should push all tags once"
    push_command="$(<"$push_log")"
    assert_eq "push origin -f --tags" "$push_command" "backfill should use one full tag push"

    rm -rf "$repo" "$git_wrapper_dir"
}

test_backfill_base_ref_limits_to_branch_commits() {
    local repo main_sha_a main_sha_b feature_sha
    repo="$(new_repo)"
    main_sha_a="$(create_commit "$repo" "2026-04-20T09:00:00Z" "main-a")"
    main_sha_b="$(create_commit "$repo" "2026-04-21T09:00:00Z" "main-b")"
    (
        cd "$repo"
        git checkout -b feature >/dev/null
    )
    feature_sha="$(create_commit "$repo" "2026-04-24T09:00:00Z" "feature-c")"

    (
        cd "$repo"
        "$CALVER" --backfill-all --backfill-base-ref=main --apply >/dev/null

        main_tags_a="$(git tag --points-at "$main_sha_a")"
        main_tags_b="$(git tag --points-at "$main_sha_b")"
        feature_tags="$(git tag --points-at "$feature_sha")"

        assert_eq "" "$main_tags_a" "main ancestor commit A should not be backfilled"
        assert_eq "" "$main_tags_b" "main ancestor commit B should not be backfilled"
        assert_match "$feature_tags" '[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[0-9]+' "feature commit should be tagged"
    )

    rm -rf "$repo"
}

test_backfill_empty_base_ref_defaults_to_primary_branch() {
    local repo main_sha_a main_sha_b feature_sha
    repo="$(new_repo)"
    main_sha_a="$(create_commit "$repo" "2026-04-20T09:00:00Z" "main-a")"
    main_sha_b="$(create_commit "$repo" "2026-04-21T09:00:00Z" "main-b")"
    (
        cd "$repo"
        git checkout -b feature >/dev/null
    )
    feature_sha="$(create_commit "$repo" "2026-04-24T09:00:00Z" "feature-c")"

    (
        cd "$repo"
        "$CALVER" --backfill-all --backfill-base-ref= --apply >/dev/null

        main_tags_a="$(git tag --points-at "$main_sha_a")"
        main_tags_b="$(git tag --points-at "$main_sha_b")"
        feature_tags="$(git tag --points-at "$feature_sha")"

        assert_eq "" "$main_tags_a" "main ancestor commit A should not be backfilled when base ref is empty"
        assert_eq "" "$main_tags_b" "main ancestor commit B should not be backfilled when base ref is empty"
        assert_match "$feature_tags" '[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[0-9]+' "feature commit should be tagged when base ref is empty"
    )

    rm -rf "$repo"
}

test_non_git_show_calendar_still_works() {
    local tmp actual explicit
    tmp="$(mktemp -d)"
    (
        cd "$tmp"
        actual="$(TZ=UTC "$CALVER" --show=calendar)"
        explicit="$(TZ=UTC "$CALVER" --show=calendar --date=2026-04-24T00:00:00Z)"
        assert_match "$actual" '^[0-9]{4}\.[0-9]{2}\.[0-9]{2}$' "non-git calendar format should still be valid"
        assert_eq "2026.17.05" "$explicit" "explicit date should be honored in non-git usage"
    )
    rm -rf "$tmp"
}

test_clear_branch_tags_flag_removes_branch_tags() {
    local repo base_sha feature_sha
    repo="$(new_repo)"
    base_sha="$(create_commit "$repo" "2026-04-20T10:00:00Z" "base")"
    (
        cd "$repo"
        git checkout -b feature >/dev/null
    )
    feature_sha="$(create_commit "$repo" "2026-04-24T10:00:00Z" "feature-work")"

    (
        cd "$repo"
        git tag "keep-base" "$base_sha"
        git tag "drop-feature" "$feature_sha"

        "$CALVER" --backfill-all --backfill-base-ref=main --clear-branch-tags --apply >/dev/null

        remaining_base="$(git tag -l "keep-base")"
        remaining_feature="$(git tag -l "drop-feature")"
        assert_eq "keep-base" "$remaining_base" "base commit tag should remain"
        assert_eq "" "$remaining_feature" "feature commit tag should be cleared"
    )

    rm -rf "$repo"
}

main() {
    test_git_default_uses_head_timestamp
    test_backfill_tags_recent_commits
    test_backfill_rerun_is_stable
    test_base_tag_tracks_latest_commit
    test_default_base_tag_tracks_latest_commit
    test_backfill_all_tags_entire_history
    test_backfill_pushes_tags_once
    test_backfill_base_ref_limits_to_branch_commits
    test_backfill_empty_base_ref_defaults_to_primary_branch
    test_non_git_show_calendar_still_works
    test_clear_branch_tags_flag_removes_branch_tags
    echo "All tests passed."
}

main "$@"
