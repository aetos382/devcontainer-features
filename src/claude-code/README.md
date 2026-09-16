
# Claude Code (claude-code)

Installs the Claude Code CLI from Anthropic's release bucket, verifying the GPG signature on the release manifest and the SHA256 checksum of the binary, and optionally persists settings, credentials, and session history across container rebuilds using a named volume scoped to the dev container.

## Example Usage

```json
"features": {
    "ghcr.io/aetos382/devcontainer-features/claude-code:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | Version of Claude Code to install. Either a release channel ('latest' or 'stable') or an exact version such as '2.1.267'. Exact versions must be 2.1.89 or later, the first release with a signed manifest. | string | latest |
| persistence | Persist Claude Code settings, credentials, and session history by pointing CLAUDE_CONFIG_DIR at a named volume scoped to the dev container. | boolean | true |

## Customizations

### VS Code Extensions

- `anthropic.claude-code`

## How it works

### Installing the CLI

- The binary comes from Anthropic's release bucket at `https://downloads.claude.ai/claude-code-releases`. A release channel (`latest`, `stable`) resolves through that channel's pointer document; an exact version is used as given.
- `manifest.json` is verified against its detached signature `manifest.json.sig`, requiring exactly one signature, and that it be a good signature from Anthropic's release signing key `31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE` made with a key that is neither revoked nor expired. The manifest lists a SHA256 for every platform binary, so verifying the manifest transitively verifies the download.
- The binary is then checked against that SHA256, run once to confirm it reports the expected version, and installed as `/usr/local/bin/claude`, owned by root with mode 755. It is available to every user in the container.
- The official installer at `https://claude.ai/install.sh` is deliberately not used. It is a bootstrapper that downloads the newest binary, checks it against `manifest.json`, and hands the real work to `claude install`; it never verifies `manifest.json.sig`, and it installs under a single user's home directory.
- Exact versions must be 2.1.89 or later. Earlier releases publish `manifest.json` without a signature, and this feature refuses to install what it cannot verify.

### Persisting settings

- A named volume `claude-code-${devcontainerId}` is mounted at `/var/lib/claude-code`. Each dev container gets its own volume, so settings such as MCP servers are not shared between dev containers.
- `CLAUDE_CONFIG_DIR` defaults to the mount point through `/etc/profile.d/claude-code.sh`. Claude Code then stores both the `~/.claude` contents and `.claude.json` (OAuth account, global settings) inside the volume.
- The mount point is owned by the remote user. Ownership is set at build time and re-checked by the feature's entrypoint on every container start, so it follows UID changes made by `updateRemoteUserUID`. If the entrypoint could not fix ownership (for example, because the container does not run as root), `postCreateCommand` retries recursively with passwordless `sudo`, and fails with an error if the mount point or its contents are still not owned by the remote user.

## Updating

A dev container is normally rebuilt rather than updated in place, and a rebuild is the intended way to move to a newer Claude Code.

This feature does not touch `DISABLE_AUTOUPDATER`, so Claude Code's updater keeps running. It never modifies `/usr/local/bin/claude`; instead it installs the new version under the running user's `~/.local/share/claude/versions/` and points `~/.local/bin/claude` at it. Whether that copy is used depends on `PATH`. On Debian/Ubuntu-based images, a non-root user's `~/.profile` puts `~/.local/bin` ahead of `/usr/local/bin` in login shells started after that directory exists, so those shells run the newer copy; root's `.profile` does not, so root keeps running the binary this feature installed. Nothing breaks either way, but the container may hold two installations, and the user-local one is lost on rebuild.

To update without rebuilding, run `claude install latest` (or `stable`, or an exact version) as the remote user. Note that `claude install` does its own download and verification; it does not go through the signature check described above.

To keep only the installation this feature made, set `DISABLE_AUTOUPDATER` to `1` via `containerEnv` or `remoteEnv` in your `devcontainer.json`.

## Limitations

- Only tested on Debian/Ubuntu-based images on x86_64 and aarch64. The scripts rely on GNU coreutils and findutils (`stat -c`, `find ... -quit`, etc.) and `/etc/profile.d`. musl builds are selected automatically when a musl libc is detected, but Alpine is untested and additionally needs `libgcc`, `libstdc++`, and `ripgrep` for Claude Code itself.
- `persistence` cannot control the mount. A feature's `mounts` is a static array, so the named volume is created even with `persistence: false`; the feature simply leaves it unused and does not set `CLAUDE_CONFIG_DIR`.
- If `CLAUDE_CONFIG_DIR` is already set (via Dockerfile `ENV` or `containerEnv`) to a different path, your value is kept and this feature persists nothing. A warning is printed from `postCreateCommand`.
- `CLAUDE_CONFIG_DIR` is delivered through `/etc/profile.d`. It does not reach processes when `"userEnvProbe": "none"` is set, and it is not read at all if the remote user's login shell is zsh (Debian/Ubuntu's zsh does not source `/etc/profile.d` by default). A warning is printed from `postCreateCommand` in this case as well.
- The mount point cannot be changed.
- The volume contents are not visible from the VS Code file explorer. Use `docker volume` commands to inspect or delete them. To reset: find the exact volume name with `docker volume ls --filter name=claude-code-` (`docker volume rm` does not accept wildcards), remove the container that references it (a stopped container still holds the reference, so `docker rm <container>` is required, not just stopping it), then `docker volume rm <volume>`.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/aetos382/devcontainer-features/blob/main/src/claude-code/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
