#!/usr/bin/env bash
# Installs a patched opencode build from this repo's releases into ~/.opencode/bin.
# Accepts the same flags opencode's own updater passes to the official installer.
#   curl -fsSL https://raw.githubusercontent.com/sidevesh/opencode-patched/main/install.sh | bash
set -euo pipefail

REPO="sidevesh/opencode-patched"
version=""
while [ $# -gt 0 ]; do
  case "$1" in
    --version) version="${2:?--version needs a value}"; shift 2 ;;
    --version=*) version="${1#*=}"; shift ;;
    --no-modify-path) shift ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) platform="darwin-arm64" ;;
  Linux-x86_64) platform="linux-x64" ;;
  *) echo "Only macOS arm64 and Linux x64 builds are published." >&2; exit 1 ;;
esac

if [ -z "$version" ]; then
  version="$(curl -fsSL "https://github.com/$REPO/releases/latest/download/update.json" | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p')"
  [ -n "$version" ] || { echo "Could not determine the latest version." >&2; exit 1; }
fi
version="${version#v}"

base="https://github.com/$REPO/releases/download/v$version"
bin_dir="$HOME/.opencode/bin"
mkdir -p "$bin_dir"

tmp="$(mktemp "$bin_dir/.opencode.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
curl -fsSL -o "$tmp" "$base/opencode-$platform"
expected="$(curl -fsSL "$base/SHA256SUMS" | awk -v f="opencode-$platform" '$2 == f { print $1 }')"
actual="$({ shasum -a 256 "$tmp" 2>/dev/null || sha256sum "$tmp"; } | awk '{ print $1 }')"
if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
  echo "Checksum mismatch for opencode $version." >&2
  exit 1
fi

chmod 755 "$tmp"
mv -f "$tmp" "$bin_dir/opencode"
trap - EXIT

if [ ! -e "$bin_dir/opencode2" ]; then
  printf '#!/bin/sh\nexec "$(dirname "$0")/opencode" "$@"\n' >"$bin_dir/opencode2"
  chmod 755 "$bin_dir/opencode2"
fi

echo "Installed opencode $version (patched) to $bin_dir/opencode"
