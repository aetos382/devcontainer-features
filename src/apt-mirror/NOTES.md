## How it works

- Rewrites the distribution's default archive to the given `mirror` URL, and its default security archive to the given `security_mirror` URL, wherever they appear in `/etc/apt/sources.list.d/*.sources`. Those are the deb822-format files where Ubuntu 24.04 and later and Debian 12 and later keep their default sources.

  | Distribution | `mirror` replaces | `security_mirror` replaces |
  |---|---|---|
  | Ubuntu | `archive.ubuntu.com/ubuntu` | `security.ubuntu.com/ubuntu` |
  | Debian | `deb.debian.org/debian` | `deb.debian.org/debian-security` |

- The two options are independent, and each one left empty (the default) keeps that archive where it is. `security_mirror` is separate because mirrors sync on their own schedule and can lag behind the distribution's own security server, and because on Debian the security archive is a different one that an ordinary mirror need not carry. On Ubuntu, where a mirror carries both, give both options the same URL to move both.
- Runs `apt-get update` afterward to confirm the new sources actually work, rather than leaving that discovery to whichever later feature happens to run `apt-get` first. Uses `-o APT::Update::Error-Mode=any` because apt-get update's default mode can downgrade a failed fetch to a warning when an older cached index is still around to fall back on.
- Fails the build if that `apt-get update` doesn't succeed, so an unusable URL never produces an image with apt sources that don't work.
- Removes the package lists that `apt-get update` fetched once the check succeeds, so they don't add weight to the image. Later features run `apt-get update` themselves before installing anything.
- Does nothing if both options are left empty.
- Installing the feature again on the same image, which happens on top of an image prebuilt with it or when another feature pulls it in through `dependsOn`, succeeds. With the same URLs it changes nothing. With different ones it also changes nothing, and prints a warning that the new URL is not in effect: see Limitations.

## Requirements

Uses only `grep`, `sed`, `awk`, and `apt-get`, all of which every Ubuntu and Debian image ships with, so nothing is installed.

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

- Tested on Ubuntu 26.04 and 24.04, including the `mcr.microsoft.com/devcontainers/base` images for those releases, and on Debian 13 and 12. Other releases are untested. Other distributions are refused: the feature fails when an option is set and `ID` in `/etc/os-release` is neither `ubuntu` nor `debian`.
- Tested on amd64 only.
- On Ubuntu for arm64 (and other ports architectures), both options are left without effect, with a warning rather than an error. Those images take every package, security updates included, from `ports.ubuntu.com/ubuntu-ports`, which is a different host and path from the ones above and does not tell the two archives apart. Debian uses the same hosts on every architecture.
- Sources in the one-line format (`/etc/apt/sources.list`, `/etc/apt/sources.list.d/*.list`) are not rewritten. That format is the default on Ubuntu 22.04 and earlier and on Debian 11 and earlier, so on those releases the feature prints a warning and changes nothing. Versions 1.x rewrote them.
- Only the default hosts in the table above are recognized. Sources that name something else are left as-is, with a warning rather than an error, so that the build doesn't break. This is the case for a base image already pointed at a non-default mirror, and equally after an earlier run of this feature: a second run cannot switch from one mirror to another. When the sources already name the requested URL, there is no warning.
- Each URL must start with `http://` or `https://` and must not contain whitespace or control characters; the feature fails otherwise.
- Versions 1.x had a boolean `include_security` option instead of `security_mirror`, and supported Ubuntu only. To get what `include_security: true` did, set `security_mirror` to the same URL as `mirror`.
