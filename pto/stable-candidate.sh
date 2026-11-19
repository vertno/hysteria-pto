#!/usr/bin/env bash
# Prepare a candidate locally on the Actions runner. This job has read access only.
set -euo pipefail
upstream=HyNetworks/hysteria
stable=$(gh api --paginate --slurp "repos/$upstream/releases?per_page=100" |
  jq -er '[.[][] | select(.draft == false and .prerelease == false) | .tag_name |
    select(test("^app/v2\\.[0-9]+\\.[0-9]+$"))] | max_by(ltrimstr("app/v") | split(".") | map(tonumber)) // empty')
tag="pto-${stable#app/}-1"
released=$(gh api --paginate --slurp "repos/$GITHUB_REPOSITORY/releases?per_page=100" |
  jq -r --arg tag "$tag" 'any(.[][]; .tag_name == $tag and .draft == false and .prerelease == false)')
echo "Official release: $stable. Downstream: $tag. Published: $released." >> "$GITHUB_STEP_SUMMARY"
if [[ "$released" == true ]]; then
    echo "build=false" >> "$GITHUB_OUTPUT"
    heartbeat=refs/remotes/origin/automation/stable-check
    if ! git rev-parse --verify --quiet "$heartbeat" >/dev/null; then heartbeat=HEAD; fi
    if (( $(date +%s) - $(git show -s --format=%ct "$heartbeat") >= 35*86400 )); then
        echo "heartbeat=true" >> "$GITHUB_OUTPUT"
    fi
    exit 0
fi

git fetch --no-tags origin refs/heads/pto
base=$(git rev-parse FETCH_HEAD)
git switch -C stable-candidate "$base"
git fetch --no-tags "https://github.com/$upstream.git" "refs/tags/$stable:refs/tags/$stable"
official=$(git rev-parse "$stable^{commit}")
git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
if git show-ref --verify --quiet "refs/tags/$tag"; then
    # Resume a previous run (including an existing draft) using exactly the tagged source.
    git switch --detach "$tag^{commit}"
    git merge-base --is-ancestor HEAD "$base"
elif ! git merge-base --is-ancestor "$official" HEAD; then
    git merge --no-commit --no-ff "$official" || git rev-parse -q --verify MERGE_HEAD >/dev/null
    # The fork owns its release machinery. Other merge conflicts require review.
    git restore --source="$base" --staged --worktree -- .github/workflows pto
    if [[ -n "$(git ls-files --unmerged)" ]]; then git diff --name-only --diff-filter=U; exit 1; fi
    # Retain the pinned compiler unless the new modules require a newer release.
    required=$(awk '$1=="go" || $1=="toolchain" {sub(/^go/,"",$2); print $2}' go.work {app,core,extras}/go.mod |
        grep -E '^[0-9]+\.[0-9]+(\.[0-9]+)?$' | sed -E '/^[0-9]+\.[0-9]+$/s/$/.0/' | sort -V | tail -1)
    printf '%s\n' "$required" "$(cat pto/go-version)" | sort -V | tail -1 > "$RUNNER_TEMP/go-pin"
    cp "$RUNNER_TEMP/go-pin" pto/go-version
    git add pto/go-version
    git commit -m "Merge official Hysteria $stable"
    git bundle create "$RUNNER_TEMP/candidate.bundle" refs/heads/stable-candidate "^$base"
fi
git merge-base --is-ancestor "$official" HEAD
{
    echo "build=true"
    echo "tag=$tag"
    echo "stable=$stable"
    echo "official=$official"
    echo "base=$base"
    echo "commit=$(git rev-parse HEAD)"
} >> "$GITHUB_OUTPUT"
