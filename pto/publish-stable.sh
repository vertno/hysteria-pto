#!/usr/bin/env bash
# Run on a fresh runner with the verified artifacts; never run the candidate with a write token.
set -euo pipefail
files=(hysteria-pto-linux-amd64 build-info.txt modules.txt version.txt SHA256SUMS)
cd "$RUNNER_TEMP/release-files"
sha256sum --check SHA256SUMS
grep -Fx "upstream_tag=$STABLE" build-info.txt
grep -Fx "upstream_commit=$OFFICIAL" build-info.txt
grep -Fx "fork_commit=$CANDIDATE" build-info.txt
cd "$GITHUB_WORKSPACE"
if [[ -f "$RUNNER_TEMP/release-files/candidate.bundle" ]]; then
    git bundle verify "$RUNNER_TEMP/release-files/candidate.bundle"
    git fetch "$RUNNER_TEMP/release-files/candidate.bundle" refs/heads/stable-candidate
    test "$(git rev-parse FETCH_HEAD)" = "$CANDIDATE"
fi
git fetch --no-tags origin refs/heads/pto
test "$(git rev-parse FETCH_HEAD)" = "$BASE"
if git show-ref --verify --quiet "refs/tags/$TAG"; then
    test "$(git rev-parse "$TAG^{commit}")" = "$CANDIDATE"
    git merge-base --is-ancestor "$CANDIDATE" "$BASE"
else
    git merge-base --is-ancestor "$BASE" "$CANDIDATE"
    git push --atomic --force-with-lease="refs/heads/pto:$BASE" origin \
      "$CANDIDATE:refs/heads/pto" "$CANDIDATE:refs/tags/$TAG"
fi
cd "$RUNNER_TEMP/release-files"
info=$(gh api --paginate --slurp "repos/$GITHUB_REPOSITORY/releases?per_page=100" |
    jq -c --arg tag "$TAG" '[.[][] | select(.tag_name == $tag)][0]')
if [[ "$info" == null ]]; then
    gh release create "$TAG" --repo "$GITHUB_REPOSITORY" --verify-tag --draft \
        --title "$TAG" --notes "基于官方稳定版 [$STABLE](https://github.com/HyNetworks/hysteria/releases/tag/$STABLE)，保留 PTO 补丁。Linux amd64 程序、SHA-256 和构建清单见附件。"
else
    jq -e '.draft and (.prerelease | not)' <<< "$info" >/dev/null
    old=$(jq -r '.assets[] | select(.name=="hysteria-pto-linux-amd64") | .digest' <<< "$info")
    [[ -z "$old" || "$old" == "sha256:$(sha256sum hysteria-pto-linux-amd64 | cut -d' ' -f1)" ]]
fi
gh release upload "$TAG" --repo "$GITHUB_REPOSITORY" --clobber "${files[@]}"
assets=$(gh release view "$TAG" --repo "$GITHUB_REPOSITORY" --json assets)
for f in "${files[@]}"; do
    digest=$(sha256sum "$f" | cut -d' ' -f1)
    jq -e --arg f "$f" --arg d "sha256:$digest" 'any(.assets[]; .name==$f and .digest==$d)' <<< "$assets" >/dev/null
done
gh release edit "$TAG" --repo "$GITHUB_REPOSITORY" --draft=false --latest
