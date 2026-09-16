## How it works

- Rewrites `archive.ubuntu.com` to the given `mirror` URL wherever it appears in `/etc/apt/sources.list` and `/etc/apt/sources.list.d/*.list` (classic one-line format) or `/etc/apt/sources.list.d/*.sources` (deb822 format, the default on Ubuntu 24.04+).
- Also rewrites `security.ubuntu.com` the same way if `include_security` is set to `true`. It defaults to `false`: most Ubuntu mirrors, regional ones included, don't carry security updates, so leaving `security.ubuntu.com` alone is the safer default.
- Runs `apt-get update` afterward to confirm the mirror is actually reachable, rather than leaving that discovery to whichever later feature happens to run `apt-get` first. Uses `-o APT::Update::Error-Mode=any` (ignored by apt versions that don't recognize the option) because apt-get update's default mode can downgrade a failed fetch to a warning when an older cached index is still around to fall back on.
- Restores the original files and fails if that `apt-get update` doesn't succeed, so an unusable `mirror` never leaves the image with apt sources that don't work.
- Does nothing if `mirror` is left empty (the default).

## Install order

This feature only helps if it runs before any other feature that installs packages with `apt-get`. `installsAfter` only lets a feature declare what it must follow, not what must follow it, so this feature cannot force that order on its own.

Instead, list this feature first in [`overrideFeatureInstallOrder`](https://containers.dev/implementors/features/#installation-order) in `devcontainer.json`:

```json
"overrideFeatureInstallOrder": [
    "ghcr.io/aetos382/devcontainer-features/apt-mirror"
]
```

`overrideFeatureInstallOrder` does not have to list every feature in use: entries not listed still install afterward, in whatever order their own dependency resolution produces.

## Limitations

- Refuses to run on a non-Ubuntu image (checked via `ID=ubuntu` in `/etc/os-release`); Debian's `deb.debian.org` is not rewritten.
- Only `archive.ubuntu.com` and, with `include_security`, `security.ubuntu.com` are recognized. A base image already pointed at a non-default mirror is left as-is, with a warning rather than an error, so that it doesn't break the build.
- arm64 and armhf images are left as-is for the same reason: they use `ports.ubuntu.com/ubuntu-ports`, whose path differs from `archive.ubuntu.com/ubuntu`, so one `mirror` value cannot stand in for both.
- `mirror` must start with `http://` or `https://`; the feature fails otherwise.
