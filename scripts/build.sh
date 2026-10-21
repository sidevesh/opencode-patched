#!/usr/bin/env bash
# Builds a patched opencode CLI for macOS arm64.
# Usage: scripts/build.sh <opencode-version>   (e.g. 2.1.2)
# Needs: git, jq, curl. Fetches the bun and zig versions the sources ask for.
set -euo pipefail

VERSION="${1:?usage: scripts/build.sh <opencode-version>}"
VERSION="${VERSION#v}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${WORK:-$ROOT/.work}"
OUT="${OUT:-$ROOT/dist}"
rm -rf "$WORK" "$OUT"
mkdir -p "$WORK" "$OUT"

apply_patches() {
  local repo="$1" dir="$2"
  local patch name
  for patch in "$dir"/*.patch; do
    [ -e "$patch" ] || continue
    name="$(basename "$patch")"
    if git -C "$repo" apply --reverse --check "$patch" 2>/dev/null; then
      echo "already upstream, skipping: $name"
      echo "- \`$name\`: already upstream, skipped" >>"$OUT/patches.md"
    elif git -C "$repo" apply --check "$patch"; then
      git -C "$repo" apply "$patch"
      echo "applied: $name"
      echo "- \`$name\`: applied" >>"$OUT/patches.md"
    else
      echo "::error::$name no longer applies to $(basename "$repo") — refresh the patch"
      exit 1
    fi
  done
}

echo "== opencode v$VERSION"
git clone --quiet --depth 1 --branch "v$VERSION" https://github.com/anomalyco/opencode.git "$WORK/opencode"
OPENTUI_VERSION="$(jq -r '[.. | objects | .["@opentui/core"]? | strings | select(test("^[0-9]"))][0]' "$WORK/opencode/package.json")"
[ -n "$OPENTUI_VERSION" ] && [ "$OPENTUI_VERSION" != "null" ] || { echo "::error::could not find pinned @opentui/core version"; exit 1; }
echo "== opentui v$OPENTUI_VERSION"
git clone --quiet --depth 1 --branch "v$OPENTUI_VERSION" https://github.com/anomalyco/opentui.git "$WORK/opentui"

TOOLS="$WORK/tools"
mkdir -p "$TOOLS"
BUN_VERSION="$(jq -r '.packageManager' "$WORK/opencode/package.json" | cut -d@ -f2)"
ZIG_VERSION="$(sed -n 's/.*\.minimum_zig_version = "\([^"]*\)".*/\1/p' "$WORK/opentui/packages/native/build.zig.zon")"
[ -n "$ZIG_VERSION" ] || { echo "::error::could not read opentui's minimum zig version"; exit 1; }
echo "== bun $BUN_VERSION, zig $ZIG_VERSION"
curl -fsSL -o "$TOOLS/bun.zip" "https://github.com/oven-sh/bun/releases/download/bun-v$BUN_VERSION/bun-darwin-aarch64.zip"
unzip -q "$TOOLS/bun.zip" -d "$TOOLS"
ln -sf bun "$TOOLS/bun-darwin-aarch64/bunx"
curl -fsSL "https://ziglang.org/download/$ZIG_VERSION/zig-aarch64-macos-$ZIG_VERSION.tar.xz" | tar -xJ -C "$TOOLS"
export PATH="$TOOLS/bun-darwin-aarch64:$TOOLS/zig-aarch64-macos-$ZIG_VERSION:$PATH"
bun --version
zig version

: >"$OUT/patches.md"
apply_patches "$WORK/opentui" "$ROOT/patches/opentui"
apply_patches "$WORK/opencode" "$ROOT/patches/opencode"

echo "== building opentui"
(
  cd "$WORK/opentui"
  bun install
  cd packages/native && bun run build
  cd ../core && bun scripts/build.ts --native --skip-zig && bun run build:lib
)
PATCHED_DYLIB="$WORK/opentui/packages/native/lib/aarch64-macos/libopentui.dylib"
[ -f "$PATCHED_DYLIB" ] || { echo "::error::native build produced no dylib"; exit 1; }

echo "== installing opencode dependencies"
(cd "$WORK/opencode" && bun install)

# opencode depends on the published @opentui packages; swap in our build of the
# patched pieces (core's JS dist and the native library).
echo "== overlaying patched opentui"
STORE="$WORK/opencode/node_modules/.bun"
overlaid=0
# The published package is core's dist/ directory, so its files sit at the package root.
for dir in "$STORE"/@opentui+core@"$OPENTUI_VERSION"*/node_modules/@opentui/core; do
  [ -f "$dir/package.json" ] || continue
  cp -R "$WORK/opentui/packages/core/dist/." "$dir/"
  overlaid=$((overlaid + 1))
done
[ "$overlaid" -gt 0 ] || { echo "::error::no installed @opentui/core@$OPENTUI_VERSION found to overlay"; exit 1; }
NATIVE_PKG="$STORE/@opentui+core-darwin-arm64@$OPENTUI_VERSION/node_modules/@opentui/core-darwin-arm64"
[ -f "$NATIVE_PKG/libopentui.dylib" ] || { echo "::error::no installed native opentui package found"; exit 1; }
cp "$PATCHED_DYLIB" "$NATIVE_PKG/libopentui.dylib"

echo "== building opencode cli"
(
  cd "$WORK/opencode/packages/cli"
  OPENCODE_VERSION="$VERSION" OPENCODE_CHANNEL=latest BUN_COMPILE_RELEASE="bun-v$BUN_VERSION" \
    bun run script/build.ts --single --target=opencode-darwin-arm64 --skip-install
)

BIN="$WORK/opencode/packages/cli/dist/cli-darwin-arm64/bin/opencode"
codesign --force --sign - "$BIN"
codesign --verify "$BIN"
reported="$("$BIN" --version)"
[ "$reported" = "opencode v$VERSION" ] || { echo "::error::built binary reports '$reported', expected 'opencode v$VERSION'"; exit 1; }
if grep -q "01-theme-mode-poll-fallback.patch\`: applied" "$OUT/patches.md" && ! grep -aq "themePollTimeoutId" "$BIN"; then
  echo "::error::theme-mode poll fix is missing from the built binary"
  exit 1
fi
cp "$BIN" "$OUT/opencode-darwin-arm64"
(cd "$OUT" && shasum -a 256 opencode-darwin-arm64 >SHA256SUMS)
jq -n --arg v "$VERSION" '{version: $v, metadata: {package: "@opencode/cli"}}' >"$OUT/update.json"
echo "$OPENTUI_VERSION" >"$OUT/opentui-version"
echo "== done: $OUT"
