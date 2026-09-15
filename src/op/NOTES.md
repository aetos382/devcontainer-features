## How it works

- Downloads `op_linux_<arch>_v<version>.zip` from 1Password's distribution host, verifies the `op.sig` that ships inside the archive against 1Password's code signing key, and installs the binary to `/usr/local/bin/op` (owned by root, mode 755).
- The signing key's fingerprint (`3FEF9748469ADBE15DA7CA80AC2D62742012EA22`, `Code signing for 1Password <codesign@1password.com>`) is pinned in `install.sh`. Without pinning, a key served alongside a tampered binary would verify just as happily.
- When `version` names an exact version, the downloaded binary has to report that version or the install fails. The signature proves the binary is one 1Password published; the version appears only in the URL and the file name, neither of which is signed, so this is what keeps a pinned build from silently getting a different, equally well-signed release.
- No apt repository, keyring, or `debsig-verify` policy is added to the image. `apt-get upgrade` therefore cannot move the installed version, and the image's package sources say nothing about 1Password.
- `curl`, `ca-certificates`, `unzip`, and `gnupg` are installed with `apt-get` only when missing. `curl`, `unzip`, and `gnupg` are needed for the install alone. `ca-certificates` has to stay: `op` is a single self-contained binary, but like any Go program it reads the system trust store at runtime, so removing it breaks every command that reaches 1Password.

## Authentication

This feature installs the CLI only. It does not authenticate, and it deliberately does not accept a token as an option — option values are written to `devcontainer-features.env` during the build and would be baked into an image layer.

Inside a container the 1Password desktop app integration (and therefore biometric unlock) is unavailable, so use a service account and provide `OP_SERVICE_ACCOUNT_TOKEN` through the container's environment:

- **Codespaces**: a user- or repository-level Codespaces secret arrives as an environment variable, so nothing further is required.
- **Local dev containers**: pass it per project, for example `"remoteEnv": { "OP_SERVICE_ACCOUNT_TOKEN": "${localEnv:OP_SERVICE_ACCOUNT_TOKEN}" }`. There is no user setting that applies an environment variable to every dev container the way `dev.containers.defaultFeatures` applies Features ([microsoft/vscode-remote-release#4538](https://github.com/microsoft/vscode-remote-release/issues/4538)).

Scope the service account narrowly: read-only, and limited to the vault holding the secrets the container actually needs. Anything running in the container can read the token.

## Limitations

- Only tested on Debian/Ubuntu-based images. On images without `apt-get`, install `curl`, `ca-certificates`, `unzip`, and `gnupg` yourself; the feature fails with a message naming what is missing.
- Linux only, for `amd64`, `arm64`, `arm` (armv7), and `386`.
- 1Password CLI 2.x only. Both the distribution path (`op2`) and the update channel (`CLI2`) that `install.sh` uses are specific to version 2, so `latest` never resolves past 2.x; a 3.x release would need changes here.
- Not every patch version is published for download — for example `2.38.1` exists while `2.38.0` does not. Confirm that a version is available before pinning it.
- `version: latest` resolves through the update-check endpoint the CLI itself uses, which is not a documented API. Pin an exact version for reproducible builds.
- Shell completion is not installed.
