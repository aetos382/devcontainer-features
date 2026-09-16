
# Locale (locale)

Generates a UTF-8 locale and sets LANG, LANGUAGE, and LC_ALL for interactive shells.

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

- Installs the `locales` package with `apt-get` if `localedef` is not already available, generates the requested locale with `localedef -i <locale> -f UTF-8 <locale>.UTF-8`, and records it as the system default with `update-locale`.
- `LANG`, `LANGUAGE`, and `LC_ALL` are exported unconditionally from `/etc/profile.d/locale.sh` for interactive shells.

## Limitations

- Only tested on Debian/Ubuntu-based images.
- Only UTF-8 locales are supported; the `.UTF-8` suffix is appended automatically and must not be included in the `locale` option.
- `LANG`, `LANGUAGE`, and `LC_ALL` are exported unconditionally, overriding a value set through `containerEnv` for any interactive shell that reads `/etc/profile.d` (see below). Debian/Ubuntu base images already export `LANG` themselves, so a guard that only fills in an unset value would never fire; there is no way to tell that inherited default apart from a value the user actually wants kept, so this feature's own `locale` option is treated as the deciding one.
- `/etc/profile.d` is not read at all if the remote user's login shell is zsh (Debian/Ubuntu's zsh does not source `/etc/profile.d` by default), and is skipped entirely when `"userEnvProbe": "none"` is set. In both cases, only `update-locale`'s system-wide default takes effect, and only for anything that goes through PAM (e.g. an actual login) — not for a login shell started outside PAM such as VS Code Server.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/aetos382/devcontainer-features/blob/main/src/locale/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
