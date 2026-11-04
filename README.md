# opencode-patched

Stock [opencode](https://github.com/anomalyco/opencode) releases rebuilt with a few fixes that aren't upstream yet. A scheduled workflow checks for a new opencode release every 6 hours, applies the patches, builds a macOS arm64 binary and publishes it here under the same version number.

## Patches

- `patches/opentui/01-theme-mode-poll-fallback.patch`: re-checks the terminal's background color every 3 seconds, so light/dark appearance changes are picked up live under iTerm2's `tmux -CC`, where no change notification ever arrives. Not accepted upstream (anomalyco/opentui#1733); the underlying problem is tracked in anomalyco/opentui#1732.
- `patches/opencode/01-updater-use-fork-releases.patch`: points opencode's built-in update check and installer at this repo, so `opencode upgrade` and update notifications keep you on patched builds.

`patches/disabled/` holds patches that are kept for reference but not applied.

When a patch lands upstream, the build detects it and skips it. If a patch stops applying, the build fails, nothing is published, and the workflow opens a `build-failure` issue here.

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
