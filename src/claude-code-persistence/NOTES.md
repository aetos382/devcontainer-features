## How it works

- A named volume `claude-code-persistence-${devcontainerId}` is mounted at `/var/lib/claude-code-persistence`. Each dev container gets its own volume, so settings such as MCP servers are not shared between repositories.
- `CLAUDE_CONFIG_DIR` defaults to the mount point through `/etc/profile.d/claude-code-persistence.sh`. Claude Code then stores both the `~/.claude` contents and `.claude.json` (OAuth account, global settings) inside the volume.
- The mount point is created and owned by the remote user at build time, so `sudo` is not required at runtime.

This feature does not install the Claude Code CLI. Use `ghcr.io/anthropics/devcontainer-features/claude-code` or `npm install -g @anthropic-ai/claude-code`.

## Limitations

- If `CLAUDE_CONFIG_DIR` is already set (via Dockerfile `ENV` or `containerEnv`) to a different path, your value is kept and this feature persists nothing. A warning is printed from `postCreateCommand`.
- `CLAUDE_CONFIG_DIR` is delivered through `/etc/profile.d`. It does not reach processes when `"userEnvProbe": "none"` is set.
- The mount point cannot be changed.
- The volume contents are not visible from the VS Code file explorer. Use `docker volume` commands to inspect or delete them. To reset, remove the `claude-code-persistence-*` volume while the container is stopped.
