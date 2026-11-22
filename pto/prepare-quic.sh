#!/usr/bin/env bash
# Give the upstream Go commands a private workspace with only quic-go replaced.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "${1:?pass a new workspace directory}"
work=$(cd "$1" && pwd)
cd "$root"
export GOWORK="$root/go.work"
cp go.work "$work/go.work"
if [[ -f go.work.sum ]]; then cp go.work.sum "$work/go.work.sum"; fi
while read -r path; do
    GOWORK="$work/go.work" go work edit "-dropuse=$path" "-use=$(realpath "$path")"
done < <(go work edit -json | jq -r '.Use[].DiskPath')
export GOWORK="$work/go.work"
module=github.com/apernet/quic-go
version=$(go list -m -f '{{if not .Replace}}{{.Version}}{{end}}' "$module")
test -n "$version"
go mod download -json "$module@$version" > "$work/module.json"
sum=$(jq -er .Sum "$work/module.json")
grep -Fqx "$module $version $sum" core/go.sum
cp -R "$(jq -er .Dir "$work/module.json")" "$work/quic-go"
chmod -R u+w "$work/quic-go"
(cd "$work/quic-go" && git apply "$root/pto/patches/quic-go-pto.patch" "$root/pto/patches/quic-go-pto-tests.patch")

go work edit -replace="$module=./quic-go"
