## How it works

- Downloads `op_linux_<arch>_v<version>.zip` from 1Password's distribution host, verifies the `op.sig` that ships inside the archive against 1Password's code signing key, and installs the binary to `/usr/local/bin/op` (owned by root, mode 755).
- The signing key's fingerprint (`3FEF9748469ADBE15DA7CA80AC2D62742012EA22`, `Code signing for 1Password <codesign@1password.com>`) is pinned in `install.sh`. Without pinning, a key served alongside a tampered binary would verify just as happily.
- No apt repository, keyring, or `debsig-verify` policy is added to the image. `apt-get upgrade` therefore cannot move the installed version, and the image's package sources say nothing about 1Password.
- `curl`, `ca-certificates`, `unzip`, and `gnupg` are installed with `apt-get` only when missing. They are build dependencies; the installed `op` is a single self-contained binary.

## Authentication

This feature installs the CLI only. It does not authenticate, and it deliberately does not accept a token as an option — option values are written to `devcontainer-features.env` during the build and would be baked into an image layer.

Inside a container the 1Password desktop app integration (and therefore biometric unlock) is unavailable, so use a service account and provide `OP_SERVICE_ACCOUNT_TOKEN` through the container's environment:

- **Codespaces**: a user- or repository-level Codespaces secret arrives as an environment variable, so nothing further is required.
- **Local dev containers**: pass it per project, for example `"remoteEnv": { "OP_SERVICE_ACCOUNT_TOKEN": "${localEnv:OP_SERVICE_ACCOUNT_TOKEN}" }`. There is no user setting that applies an environment variable to every dev container the way `dev.containers.defaultFeatures` applies Features ([microsoft/vscode-remote-release#4538](https://github.com/microsoft/vscode-remote-release/issues/4538)).

Scope the service account narrowly: read-only, and limited to the vault holding the secrets the container actually needs. Anything running in the container can read the token.

## Limitations

- Only tested on Debian/Ubuntu-based images. On images without `apt-get`, install `curl`, `ca-certificates`, `unzip`, and `gnupg` yourself; the feature fails with a message naming what is missing.
- Linux only, for `amd64`, `arm64`, `arm` (armv7), and `386`.
- Not every patch version is published for download — for example `2.38.1` exists while `2.38.0` does not. Confirm that a version is available before pinning it.
- `version: latest` resolves through the update-check endpoint the CLI itself uses, which is not a documented API. Pin an exact version for reproducible builds.
- Shell completion is not installed.
