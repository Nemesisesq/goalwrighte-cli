#!/bin/sh
# Installs one release of the Goalwrighte CLI and refuses a binary whose SHA-256 is not the
# one in that release's checksums.txt.
#
#   GOALWRIGHTE_VERSION   required: a release tag such as v1.2.3. There is no "latest".
#   GOALWRIGHTE_BIN_DIR   where goalwrighte goes; $HOME/.local/bin by default.
#   GOALWRIGHTE_RELEASES  the releases' base URL; ci/test.sh points it at a local directory.
set -eu

fail() {
	echo "install.sh: $*" >&2
	exit 1
}

version=${GOALWRIGHTE_VERSION:-}
case $version in
*[!A-Za-z0-9.+-]*) fail "GOALWRIGHTE_VERSION must be a release tag such as v1.2.3, not \"$version\"" ;; # no path
v[0-9]*.[0-9]*.[0-9]*) ;;
*) fail "GOALWRIGHTE_VERSION must be a release tag such as v1.2.3, not \"$version\"" ;;
esac

case $(uname -s) in
Linux) os=linux ;;
Darwin) os=darwin ;;
*) fail "no Goalwrighte CLI for $(uname -s)" ;;
esac
case $(uname -m) in
x86_64 | amd64) arch=amd64 ;;
aarch64 | arm64) arch=arm64 ;;
*) fail "no Goalwrighte CLI for $(uname -m)" ;;
esac

command -v curl >/dev/null || fail "curl is not installed"
if command -v sha256sum >/dev/null; then
	sha256() { sha256sum "$1" | cut -d ' ' -f 1; }
elif command -v shasum >/dev/null; then
	sha256() { shasum -a 256 "$1" | cut -d ' ' -f 1; }
else
	fail "neither sha256sum nor shasum is installed"
fi

file=goalwrighte_${os}_${arch}
base=${GOALWRIGHTE_RELEASES:-https://github.com/Nemesisesq/goalwrighte-cli/releases/download}/$version
bin_dir=${GOALWRIGHTE_BIN_DIR:-$HOME/.local/bin}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL --retry 2 -o "$tmp/$file" "$base/$file" || fail "could not download $base/$file"
curl -fsSL --retry 2 -o "$tmp/checksums.txt" "$base/checksums.txt" || fail "could not download $base/checksums.txt"

want=$(awk -v f="$file" '$2 == f { print $1 }' "$tmp/checksums.txt")
[ -n "$want" ] || fail "checksums.txt does not list $file"
got=$(sha256 "$tmp/$file")
[ "$got" = "$want" ] || fail "$file has SHA-256 $got, checksums.txt says $want; nothing was installed"

mkdir -p "$bin_dir"
chmod 755 "$tmp/$file"
mv "$tmp/$file" "$bin_dir/goalwrighte"
echo "Installed the Goalwrighte CLI $version at $bin_dir/goalwrighte"
