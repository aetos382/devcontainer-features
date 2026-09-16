# devcontainer-features

Dev Container Features by aetos382.

| Feature | Description |
|---|---|
| [apt-mirror](src/apt-mirror) | Points Ubuntu's default apt sources (archive.ubuntu.com, security.ubuntu.com) at a different mirror. |
| [claude-code-persistence](src/claude-code-persistence) | Persists Claude Code settings, credentials, and session history across container rebuilds. |
| [locale](src/locale) | Generates a UTF-8 locale and sets LANG, LANGUAGE, and LC_ALL for login shells. |
| [op](src/op) | Installs the 1Password CLI (op) from 1Password's signed release archive, without adding an apt repository. |
| [timezone](src/timezone) | Sets the system timezone by pointing /etc/localtime at the requested zoneinfo entry. |
