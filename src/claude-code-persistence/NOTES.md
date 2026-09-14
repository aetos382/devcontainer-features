## How it works

- A named volume `claude-code-persistence-${devcontainerId}` is mounted at `/var/lib/claude-code-persistence`. Each dev container gets its own volume, so settings such as MCP servers are not shared between repositories.
- `CLAUDE_CONFIG_DIR` defaults to the mount point through `/etc/profile.d/claude-code-persistence.sh`. Claude Code then stores both the `~/.claude` contents and `.claude.json` (OAuth account, global settings) inside the volume.
- The mount point is owned by the remote user. Ownership is set at build time and re-checked by the feature's entrypoint on every container start, so it follows UID changes made by `updateRemoteUserUID`. If the container does not run as root, `postCreateCommand` falls back to passwordless `sudo` and otherwise prints a warning.

This feature does not install the Claude Code CLI. Use `ghcr.io/anthropics/devcontainer-features/claude-code` or `npm install -g @anthropic-ai/claude-code`.

## Limitations

- If `CLAUDE_CONFIG_DIR` is already set (via Dockerfile `ENV` or `containerEnv`) to a different path, your value is kept and this feature persists nothing. A warning is printed from `postCreateCommand`.
- `CLAUDE_CONFIG_DIR` is delivered through `/etc/profile.d`. It does not reach processes when `"userEnvProbe": "none"` is set, and it is not read at all if the remote user's login shell is zsh (Debian/Ubuntu's zsh does not source `/etc/profile.d` by default).
- The mount point cannot be changed.
- The volume contents are not visible from the VS Code file explorer. Use `docker volume` commands to inspect or delete them. To reset: find the exact volume name with `docker volume ls --filter name=claude-code-persistence-` (`docker volume rm` does not accept wildcards), remove the container that references it (a stopped container still holds the reference, so `docker rm <container>` is required, not just stopping it), then `docker volume rm <volume>`.
