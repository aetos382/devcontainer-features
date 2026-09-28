## How it works

- Downloads `shellcheck-<version>.linux.<arch>.tar.xz` from ShellCheck's GitHub releases, verifies it against the sha256 digest pinned in `install.sh`, and installs the binary to `/usr/local/bin/shellcheck` (owned by root, mode 755).
- ShellCheck publishes no checksum files, so the pinned digests are the ones GitHub computes for the release assets. They detect a corrupted or substituted download; they are not a signature from the ShellCheck project.
- `curl`, `ca-certificates`, and `xz-utils` are installed with `apt-get` only when missing, and only for the install itself. The ShellCheck binary is statically linked and needs nothing at runtime.
- The VS Code ShellCheck extension (`timonwong.shellcheck`) is added, with `shellcheck.executablePath` pointed at the installed binary so that the extension does not fall back to the copy it bundles.

## Versioning

This feature has no `version` option. Each release of the feature installs exactly one ShellCheck version, currently **v0.11.0**, so that only one set of digests has to be maintained. A new ShellCheck release is picked up by releasing a new version of this feature.

Because `devcontainer-lock.json` pins the feature version, it pins the ShellCheck version as well. Dependabot's `devcontainers` ecosystem proposes feature updates, and with them ShellCheck updates.

## Limitations

- Only tested on Debian/Ubuntu-based images. On images without `apt-get`, install `curl`, `ca-certificates`, and `xz` yourself; the feature fails with a message naming what is missing.
- Linux only, for `x86_64` and `aarch64`.
