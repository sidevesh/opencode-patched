# opencode-patched

Stock [opencode](https://github.com/anomalyco/opencode) releases rebuilt with a few fixes that aren't upstream yet. A scheduled workflow checks for a new opencode release every 6 hours, applies the patches, builds a macOS arm64 binary and publishes it here under the same version number.

## Patches

- `patches/opentui/01-theme-mode-poll-fallback.patch`: picks up light/dark appearance changes live on terminals that never send `CSI ?997`, such as iTerm2 (anomalyco/opentui#1733).
- `patches/opentui/02-transparent-backdrop-alpha.patch`: keeps a fully transparent theme background transparent instead of rendering it opaque (anomalyco/opentui#1734).
- `patches/opencode/01-updater-use-fork-releases.patch`: points opencode's built-in update check and installer at this repo, so `opencode upgrade` and update notifications keep you on patched builds.

When a patch lands upstream, the build detects it and skips it. If a patch stops applying, the build fails and nothing is published.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/sidevesh/opencode-patched/main/install.sh | bash
```

This installs to `~/.opencode/bin/opencode`, the same place as the official installer. After that, opencode updates itself from this repo. To go back to stock opencode, run the official installer.

## Building locally

```sh
scripts/build.sh 2.1.2
```

Output goes to `dist/`. The script downloads the bun and zig versions that opencode and opentui ask for.
