## How it works

- Downloads `shellcheck-<version>.linux.<arch>.tar.gz` from ShellCheck's GitHub releases, verifies it against the sha256 digest pinned in `install.sh`, and installs the binary to `/usr/local/bin/shellcheck` (owned by root, mode 755).
- ShellCheck publishes no checksum files or signatures, so the pinned digests are sha256 digests of the release assets as they were when this feature version was prepared; for a new ShellCheck version, Renovate computes them from the assets it downloads. They detect a download that was corrupted or substituted after this feature version was released. They do not protect against a release asset that had already been tampered with when its digest was taken.
- The downloaded binary is run once before it is installed, so that a binary that cannot run on the image fails the build instead of landing on `PATH`. The version it reports is not checked separately, because the digest already pins the exact bytes.
- The VS Code ShellCheck extension (`timonwong.shellcheck`) is added, with `shellcheck.executablePath` pointed at the installed binary so that the extension does not fall back to the copy it bundles.

## Versioning

This feature has no `version` option. Each release of the feature installs exactly one ShellCheck version, currently **0.11.0**, so that only one set of digests has to be maintained. A new ShellCheck release is picked up by releasing a new version of this feature: Renovate proposes the new version together with its digests in this repository.

Because `devcontainer-lock.json` pins the feature version, it pins the ShellCheck version as well. Dependabot's `devcontainers` ecosystem proposes feature updates, and with them ShellCheck updates.

## Requirements

- The install runs as root, which the dev container build does by default.
- `curl`, `ca-certificates`, `tar`, and `gzip` are needed to download and unpack the archive. On images with `apt-get`, the missing ones are installed automatically and remain installed afterward.
- `sha256sum`, `install`, `mktemp`, and `cut` (coreutils) are assumed to be present and are not checked beforehand.
- On images without `apt-get`, provide all of the above yourself. The feature fails with a message naming what is missing among `curl`, `tar`, and `gzip`, but only warns when no CA bundle is found at `/etc/ssl/certs/ca-certificates.crt`, since such an image may keep its trust store elsewhere.
- The ShellCheck binary is statically linked and needs nothing at runtime.

## Limitations

- Tested on Ubuntu 26.04, Ubuntu 24.04, Debian 13, and Debian 12. Other distributions are not tested.
- Linux only. Tested on `x86_64` and `aarch64`. Upstream's `riscv64` and 32-bit ARM (`armv6hf`, used for `armv6l` and `armv7l`) builds are installed the same way but are not tested.
