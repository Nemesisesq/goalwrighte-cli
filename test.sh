#!/bin/sh
# Runs install.sh against a release directory made here, with a shell script standing in for
# the binary: a good release installs and runs, and a wrong checksum, a missing checksum and a
# version that is not a tag or holds a path are each refused with nothing installed.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

release=$tmp/releases/v0.0.1
mkdir -p "$release"
printf '#!/bin/sh\necho "goalwrighte stand-in $*"\n' > "$release/goalwrighte_linux_amd64"
for t in linux_arm64 darwin_amd64 darwin_arm64; do
	cp "$release/goalwrighte_linux_amd64" "$release/goalwrighte_$t"
done
sums() {
	if command -v sha256sum >/dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi
}
(cd "$release" && sums goalwrighte_* > checksums.txt)

install() {
	GOALWRIGHTE_RELEASES="file://$tmp/releases" GOALWRIGHTE_VERSION=$1 GOALWRIGHTE_BIN_DIR=$2 sh "$here/install.sh"
}
refused() {
	if install "$1" "$tmp/refused" 2>"$tmp/err"; then
		echo "FAIL: $2 was installed" >&2
		exit 1
	fi
	if [ -e "$tmp/refused/goalwrighte" ]; then
		echo "FAIL: $2 left a file behind" >&2
		exit 1
	fi
	echo "ok: $2 is refused: $(cat "$tmp/err")"
}

install v0.0.1 "$tmp/bin"
out=$("$tmp/bin/goalwrighte" version)
[ "$out" = "goalwrighte stand-in version" ] || { echo "FAIL: the installed file printed: $out" >&2; exit 1; }
echo "ok: the installed file runs"

refused latest 'the version "latest"'
refused '' 'an empty version'
refused v0.0.2 'a release that does not exist'
refused v0.0.1/../v0.0.1 'a version that holds a path'

sed 's/^[0-9a-f]\{8\}/00000000/' "$release/checksums.txt" > "$tmp/sums" && mv "$tmp/sums" "$release/checksums.txt"
refused v0.0.1 'a binary that does not match its checksum'

: > "$release/checksums.txt"
refused v0.0.1 'a binary checksums.txt does not list'

echo "ci/test.sh: all passed"
