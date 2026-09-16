
# Locale (locale)

Generates a UTF-8 locale and sets LANG for login shells.

## Example Usage

```json
"features": {
    "ghcr.io/aetos382/devcontainer-features/locale:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| locale | The locale to generate, without the '.UTF-8' suffix (e.g. 'ja_JP'). | string | en_US |

## How it works

- Installs the `locales` package with `apt-get` if `/usr/share/i18n/charmaps` is missing (that directory, not the `localedef` command, is what's actually absent on a bare Debian/Ubuntu image), validates the requested locale against `/usr/share/i18n/SUPPORTED`, registers it in `/etc/locale.gen`, generates it with `locale-gen`, and records it as the system default with `update-locale`.
- `LANG` is exported unconditionally from `/etc/profile.d/locale.sh` for login shells.
- Only `LANG` is set; `LC_ALL` and `LANGUAGE` are left untouched. `LANG` has the lowest precedence of the locale variables, so a single process can still override it. For example, to have an AI agent such as Claude Code get English command output while your own terminal uses this feature's locale, set `LC_ALL` (e.g. `C.UTF-8`) in the agent's own environment; `/etc/profile.d/locale.sh` does not reset it even when the agent runs commands through a login shell.

## Limitations

- Only tested on Debian/Ubuntu-based images.
- Only UTF-8 locales are supported; the `.UTF-8` suffix is appended automatically and must not be included in the `locale` option (a value that already includes it, such as `ja_JP.UTF-8`, is rejected with an error instead of silently producing a broken locale).
- `LANG` is exported unconditionally, overriding a value set through `containerEnv` for any login shell that reads `/etc/profile.d` (see below). Debian/Ubuntu base images already export `LANG` themselves, so a guard that only fills in an unset value would never fire; there is no way to tell that inherited default apart from a value the user actually wants kept, so this feature's own `locale` option is treated as the deciding one.
- If `LC_ALL` or `LANGUAGE` is already set by the base image or through `containerEnv`, it takes precedence over the `LANG` this feature sets, and the requested locale may not take effect.
- `/etc/profile.d` is not read at all if the remote user's login shell is zsh (Debian/Ubuntu's zsh does not source `/etc/profile.d` by default), and is skipped entirely when `"userEnvProbe": "none"` is set. In both cases, `update-locale`'s system-wide default for `LANG` still takes effect for anything that goes through PAM (e.g. an actual login), but not for a login shell started outside PAM such as VS Code Server.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/aetos382/devcontainer-features/blob/main/src/locale/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
