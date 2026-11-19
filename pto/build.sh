#!/usr/bin/env bash
# Build from the checked-out HY2 release and its checksum-verified QUIC dependency.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
out=${1:-"$root/pto-out"}
mkdir -p "$out"
out=$(cd "$out" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
module=github.com/apernet/quic-go
export GOTOOLCHAIN=local CGO_ENABLED=0
test "$(go env GOVERSION)" = "go$(cat pto/go-version)"
export GOWORK="$root/go.work"
# Resolve and build in a copy so Go's workspace checksum updates stay temporary.
cp go.work "$tmp/go.work"
if [[ -f go.work.sum ]]; then cp go.work.sum "$tmp/go.work.sum"; fi
while IFS= read -r path; do
    ln -s "$root/$path" "$tmp/$path"
done < <(go work edit -json | python3 -c 'import json, sys; print(*(m["DiskPath"] for m in json.load(sys.stdin)["Use"]), sep="\n")')
export GOWORK="$tmp/go.work"
cd "$tmp"
version=$(go list -m -f '{{if not .Replace}}{{.Version}}{{end}}' "$module")
test -n "$version"
go mod download -json "$module@$version" > "$tmp/download.json"
field() { python3 -c 'import json, sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1" < "$tmp/download.json"; }
checksum=$(field Sum)
grep -Fqx "$module $version $checksum" core/go.sum
cp -R "$(field Dir)" "$tmp/quic-go"
chmod -R u+w "$tmp/quic-go"
for patch in quic-go-pto.patch quic-go-pto-tests.patch; do
    (cd "$tmp/quic-go" && git apply --check "$root/pto/patches/$patch" && git apply "$root/pto/patches/$patch")
done

go work edit -replace="$module=./quic-go"
app=github.com/apernet/hysteria/app/v2
checked_dir=$(go list -deps -f '{{if eq .ImportPath "github.com/apernet/quic-go"}}{{.Dir}}{{end}}' "$app" | sed '/^$/d')
test "$(realpath "$checked_dir")" = "$tmp/quic-go"
go test -count=1 "$module/internal/utils" "$module/internal/ackhandler"

commit=$(git -C "$root" rev-parse HEAD)
base=${PTO_UPSTREAM_TAG:-$(git -C "$root" describe --tags --abbrev=0 --match 'app/v*')}
git -C "$root" merge-base --is-ancestor "$base^{commit}" HEAD
stamp=$(git -C "$root" show -s --format=%cI HEAD)
toolchain=$(go env GOVERSION)
pkg="$app/cmd"
binary=hysteria-pto-linux-amd64
flags="-X $pkg.appVersion=${base#app/}-pto-${commit:0:12} -X $pkg.appDate=$stamp -X $pkg.appType=pto -X $pkg.appCommit=$commit -X $pkg.appToolchain=$toolchain -X $pkg.appPlatform=linux -X $pkg.appArch=amd64 -X $pkg.libVersion=$version"
GOOS=linux GOARCH=amd64 go build -trimpath -buildvcs=false -ldflags "$flags" -o "$tmp/$binary" "$app"
go version -m "$tmp/$binary" > "$tmp/modules.txt"
grep -Fq $'=>\t./quic-go' "$tmp/modules.txt"
"$tmp/$binary" version > "$tmp/version.txt"
grep -Fq "$commit" "$tmp/version.txt"
{
    printf 'upstream_tag=%s\nupstream_commit=%s\nfork_commit=%s\ngo=%s\nquic_module=%s\nquic_version=%s\nquic_sum=%s\n' \
        "$base" "$(git -C "$root" rev-parse "$base^{commit}")" "$commit" "$toolchain" "$module" "$version" "$checksum"
    (cd "$root" && sha256sum pto/patches/*.patch)
} > "$tmp/build-info.txt"
sha256sum "$binary" build-info.txt modules.txt version.txt > SHA256SUMS
cp "$binary" build-info.txt modules.txt version.txt SHA256SUMS "$out/"
(cd "$out" && sha256sum --check SHA256SUMS)
