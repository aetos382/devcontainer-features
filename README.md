# devcontainer-features

Dev Container Features by aetos382.

| Feature | Description |
|---|---|
| [apt-mirror](src/apt-mirror) | Points Ubuntu's default apt sources (archive.ubuntu.com, security.ubuntu.com) at a different mirror. |
| [claude-code](src/claude-code) | Installs the Claude Code CLI with signature and checksum verification, and optionally persists its settings, credentials, and session history across container rebuilds. |
| [locale](src/locale) | Generates a UTF-8 locale and sets LANG for login shells. |
| [op](src/op) | Installs the 1Password CLI (op) from 1Password's signed release archive, without adding an apt repository. |
| [timezone](src/timezone) | Sets the system timezone by pointing /etc/localtime at the requested zoneinfo entry. |
