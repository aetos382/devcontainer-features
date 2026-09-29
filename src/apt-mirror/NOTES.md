## How it works

- Rewrites `archive.ubuntu.com` to the given `mirror` URL wherever it appears in `/etc/apt/sources.list` and `/etc/apt/sources.list.d/*.list` (classic one-line format) or `/etc/apt/sources.list.d/*.sources` (deb822 format, the default on Ubuntu 24.04+).
- Also rewrites `security.ubuntu.com` the same way if `include_security` is set to `true`. It defaults to `false`: mirrors sync on their own schedule and can lag behind `security.ubuntu.com`, so leaving it alone keeps security updates coming straight from Canonical without that delay.
- Runs `apt-get update` afterward to confirm the mirror is actually reachable, rather than leaving that discovery to whichever later feature happens to run `apt-get` first. Uses `-o APT::Update::Error-Mode=any` (ignored by apt versions that don't recognize the option) because apt-get update's default mode can downgrade a failed fetch to a warning when an older cached index is still around to fall back on.
- Fails the build if that `apt-get update` doesn't succeed, so an unusable `mirror` never produces an image with apt sources that don't work.
- Removes the package lists that `apt-get update` fetched once the check succeeds, so they don't add weight to the image. Later features run `apt-get update` themselves before installing anything.
- Does nothing if `mirror` is left empty (the default).

## Requirements

Uses only `grep`, `sed`, and `apt-get`, all of which every Ubuntu image ships with, so nothing is installed.

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

- Tested on Ubuntu 26.04 and 24.04, including the `mcr.microsoft.com/devcontainers/base` images for those releases. Other Ubuntu releases are untested. Releases older than 22.04, such as 20.04, are known not to work fully: their apt does not recognize `APT::Update::Error-Mode`, so an unreachable `mirror` may not fail the build.
- Ubuntu only. Unlike the other features in this collection, Debian is not supported, since it has no `archive.ubuntu.com` or `security.ubuntu.com` to rewrite. The feature refuses to run on a non-Ubuntu image (checked via `ID=ubuntu` in `/etc/os-release`) when `mirror` is set, and does nothing when it is empty.
- Only `archive.ubuntu.com` and, with `include_security`, `security.ubuntu.com` are recognized. A base image already pointed at a non-default mirror is left as-is, with a warning rather than an error, so that it doesn't break the build.
- arm64 and armhf images are left as-is for the same reason: they use `ports.ubuntu.com/ubuntu-ports`, whose path differs from `archive.ubuntu.com/ubuntu`, so one `mirror` value cannot stand in for both.
- `mirror` must start with `http://` or `https://` and must not contain whitespace or control characters; the feature fails otherwise.
