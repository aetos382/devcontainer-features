# devcontainer-features

Dev Container Features by aetos382.

| Feature | Description |
|---|---|
| [claude-code-persistence](src/claude-code-persistence) | Persists Claude Code settings, credentials, and session history across container rebuilds. |
| [op](src/op) | Installs the 1Password CLI (op) from 1Password's signed release archive, without adding an apt repository. |

## Usage

```jsonc
{
  "features": {
    "ghcr.io/anthropics/devcontainer-features/claude-code:1": {},
    "ghcr.io/aetos382/devcontainer-features/claude-code-persistence:1": {}
  }
}
```
