## How it works

- Installs the `locales` package with `apt-get` if `/usr/share/i18n/charmaps` is missing (that directory, not the `localedef` command, is what's actually absent on a bare Debian/Ubuntu image), validates the requested locale against `/usr/share/i18n/SUPPORTED`, registers it in `/etc/locale.gen`, generates it with `locale-gen`, and records it as the system default with `update-locale`.
- `LANG`, `LANGUAGE`, and `LC_ALL` are exported unconditionally from `/etc/profile.d/locale.sh` for login shells.

## Limitations

- Only tested on Debian/Ubuntu-based images.
- Only UTF-8 locales are supported; the `.UTF-8` suffix is appended automatically and must not be included in the `locale` option (a value that already includes it, such as `ja_JP.UTF-8`, is rejected with an error instead of silently producing a broken locale).
- `LANG`, `LANGUAGE`, and `LC_ALL` are exported unconditionally, overriding a value set through `containerEnv` for any login shell that reads `/etc/profile.d` (see below). Debian/Ubuntu base images already export `LANG` themselves, so a guard that only fills in an unset value would never fire; there is no way to tell that inherited default apart from a value the user actually wants kept, so this feature's own `locale` option is treated as the deciding one.
- `/etc/profile.d` is not read at all if the remote user's login shell is zsh (Debian/Ubuntu's zsh does not source `/etc/profile.d` by default), and is skipped entirely when `"userEnvProbe": "none"` is set. In both cases, `update-locale`'s system-wide defaults (`LANG`, `LANGUAGE`, and `LC_ALL`) still take effect for anything that goes through PAM (e.g. an actual login), but not for a login shell started outside PAM such as VS Code Server.
- `LANGUAGE` is set to the requested locale with its base language appended as a fallback (e.g. `ja_JP:ja`), not to the same value as `LANG`/`LC_ALL`: gettext's `LANGUAGE` is a colon-separated list of language codes, not a locale name, and does not take a codeset suffix.
