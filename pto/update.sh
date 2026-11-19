#!/usr/bin/env bash
# Prepare a local upstream release branch for review. Push it after resolving any conflicts.
set -euo pipefail
tag=${1:-}
if [[ ! "$tag" =~ ^app/v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo 'Usage: bash pto/update.sh app/vMAJOR.MINOR.PATCH' >&2
    exit 2
fi
cd "$(dirname "$0")/.."
test "$(git branch --show-current)" = pto || { echo 'Switch to pto first.' >&2; exit 1; }
test -z "$(git status --porcelain)" || { echo 'Start with a clean worktree.' >&2; exit 1; }
git fetch https://github.com/apernet/hysteria.git "refs/tags/$tag:refs/tags/$tag"
if git merge-base --is-ancestor "$tag^{commit}" HEAD; then
    echo "$tag is already included."
    exit 0
fi
git switch -c "update/${tag#app/}"
git merge --no-ff --no-edit "$tag^{commit}"
