#!/usr/bin/env bash
set -euo pipefail
upstream=HyNetworks/hysteria
versions() { gh api --paginate --slurp "repos/$1/releases?per_page=100"; }
published=$(versions "$GITHUB_REPOSITORY" | jq '[.[][] | select(.draft == false and .prerelease == false) | .tag_name]')
# Begin at the release on which the fork adopted the -patched naming.
stable=$(versions "$upstream" | jq -r --argjson published "$published" '
    [.[][] | select(.draft == false and .prerelease == false and .published_at >= "2026-11-15T01:17:25Z")
     | select(.tag_name | test("^app/v[0-9]+\\.[0-9]+\\.[0-9]+$"))
     | select(.tag_name + "-patched" as $tag | $published | index($tag) == null)]
    | sort_by(.published_at) | first.tag_name // empty')
if [[ -z "$stable" ]]; then
    echo 'Every official stable release is already published.' >> "$GITHUB_STEP_SUMMARY"
    heartbeat=refs/remotes/origin/automation/stable-check
    if ! git rev-parse --verify --quiet "$heartbeat" >/dev/null; then heartbeat=HEAD; fi
    if (( $(date +%s) - $(git show -s --format=%ct "$heartbeat") >= 35*86400 )); then
        echo 'heartbeat=true' >> "$GITHUB_OUTPUT"
    fi
    exit 0
fi

tag="$stable-patched"
base=$(git rev-parse HEAD)
git fetch --no-tags "https://github.com/$upstream.git" "refs/tags/$stable"
official=$(git rev-parse "FETCH_HEAD^{commit}")
git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
if git show-ref --verify --quiet "refs/tags/$tag"; then
    git switch --detach "$tag^{commit}"  # Resume an interrupted draft at its original source.
elif [[ "$(cat pto/upstream)" != "$official" ]]; then
    # Replay just the fork's changes onto the exact release, including maintenance releases.
    git diff --binary "$(cat pto/upstream)" "$base" -- . ':(exclude).github/workflows' ':(exclude)pto' > "$RUNNER_TEMP/fork.patch"
    git switch --detach "$official"
    git apply --3way --index "$RUNNER_TEMP/fork.patch"
    git restore --source="$base" --staged --worktree -- .github/workflows pto
    echo "$official" > pto/upstream
    git add pto/upstream
    source=$(git commit-tree "$(git write-tree)" -p "$base" -p "$official" -m "Follow official Hysteria $stable")
    git switch -C stable-candidate "$source"
    git bundle create "$RUNNER_TEMP/candidate.bundle" refs/heads/stable-candidate "^$base"
fi
test "$(cat pto/upstream)" = "$official"
latest=$(jq -nr --arg tag "$tag" --argjson published "$published" '
    [$published[] | select(test("^app/v[0-9]+\\.[0-9]+\\.[0-9]+-patched$"))] + [$tag]
    | max_by(ltrimstr("app/v") | rtrimstr("-patched") | split(".") | map(tonumber)) == $tag')
echo "Building $tag from official commit $official." >> "$GITHUB_STEP_SUMMARY"
{
    echo "build=true"
    echo "tag=$tag"
    echo "stable=$stable"
    echo "official=$official"
    echo "base=$base"
    echo "latest=$latest"
    echo "commit=$(git rev-parse HEAD)"
} >> "$GITHUB_OUTPUT"
echo "HY_APP_VERSION=${tag#app/}" >> "$GITHUB_ENV"
