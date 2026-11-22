#!/usr/bin/env bash
set -euo pipefail
root=$PWD
cd build
# Existing deployments use these five files for Linux amd64 upgrades.
cp hysteria-linux-amd64 hysteria-pto-linux-amd64
go version -m hysteria-pto-linux-amd64 > modules.txt
grep -Fq $'=>\t./quic-go' modules.txt
./hysteria-pto-linux-amd64 version > version.txt
test "$(awk '/^Version:/{print $2}' version.txt)" = "$HY_APP_VERSION"
{
    printf 'upstream_tag=%s\nupstream_commit=%s\nfork_commit=%s\ngo=%s\n' "$STABLE" "$OFFICIAL" "$(git rev-parse HEAD)" "$(go env GOVERSION)"
    jq -r '"quic_module=\(.Path)\nquic_version=\(.Version)\nquic_sum=\(.Sum)"' "$RUNNER_TEMP/pto-work/module.json"
    (cd "$root" && sha256sum pto/patches/*.patch)
} > build-info.txt
sha256sum hysteria-pto-linux-amd64 build-info.txt modules.txt version.txt > SHA256SUMS
cp "$root/scripts/install_server.sh" .
jq -n --arg version "$HY_APP_VERSION" --arg url "https://github.com/$GITHUB_REPOSITORY/releases/tag/$STABLE-patched" \
    '{lver: $version, url: $url, urgent: false}' > update.json
