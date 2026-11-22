#!/usr/bin/env bash
set -euo pipefail
out="$RUNNER_TEMP/release-files"
if [[ -f "$out/candidate.bundle" ]]; then
    git fetch "$out/candidate.bundle" refs/heads/stable-candidate
    test "$(git rev-parse FETCH_HEAD)" = "$CANDIDATE"
    rm "$out/candidate.bundle"
fi
git fetch --no-tags origin refs/heads/pto
test "$(git rev-parse FETCH_HEAD)" = "$BASE"
if git show-ref --verify --quiet "refs/tags/$TAG"; then
    test "$(git rev-parse "$TAG^{commit}")" = "$CANDIDATE"
else
    refs=("$CANDIDATE:refs/tags/$TAG")
    if [[ "$LATEST" == true ]]; then refs+=("$CANDIDATE:refs/heads/pto"); fi
    git push --atomic origin "${refs[@]}"
fi
cd "$out"
if ! gh release view "$TAG" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
    gh release create "$TAG" --repo "$GITHUB_REPOSITORY" --verify-tag --draft \
      --title "${TAG#app/}" --notes "Based on [Hysteria $STABLE](https://github.com/HyNetworks/hysteria/releases/tag/$STABLE). Includes the PTO changes and optional TCP connection audit. See [build and update details](https://github.com/$GITHUB_REPOSITORY/blob/$CANDIDATE/pto/README.md)."
fi
test "$(gh release view "$TAG" --repo "$GITHUB_REPOSITORY" --json isDraft --jq .isDraft)" = true
gh release upload "$TAG" --repo "$GITHUB_REPOSITORY" --clobber ./*
gh release edit "$TAG" --repo "$GITHUB_REPOSITORY" --draft=false --latest="$LATEST"
