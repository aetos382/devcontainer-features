# Manual negative tests for `install.sh`

`install.sh` rejects a `locale` option value that has no matching UTF-8 entry in
`/usr/share/i18n/SUPPORTED` — a typo, or a value that already includes the `.UTF-8` suffix the
feature appends itself. None of that can be covered by `devcontainer features test`: the harness
treats a failed build as a failed test, so a scenario that is supposed to fail cannot be expressed.
Run the cases below by hand whenever the validation in `install.sh` changes.

## Setup

```sh
docker run --rm -v "$PWD/src/locale:/mnt/f:ro" debian:latest sh
```

## Case A: a locale that doesn't exist

```sh
LOCALE=xx_XX sh /mnt/f/install.sh; echo "exit status: $?"
```

Expected: exit status 1, nothing written to `/etc/profile.d` or `/etc/default/locale`.

```
locale: 'xx_XX' is not a supported UTF-8 locale (checked /usr/share/i18n/SUPPORTED for 'xx_XX.UTF-8 UTF-8' and 'xx_XX UTF-8').
```

## Case B: a locale that already includes the `.UTF-8` suffix

```sh
LOCALE=ja_JP.UTF-8 sh /mnt/f/install.sh; echo "exit status: $?"
```

Expected: exit status 1, rejected explicitly before the `/usr/share/i18n/SUPPORTED` lookup — some
locales are listed there under their plain, unsuffixed name (see Case C), so a value that already
carries the suffix could otherwise coincidentally match a real entry instead of being caught.

```
locale: 'ja_JP.UTF-8' must not include the '.UTF-8' suffix; it is appended automatically.
```

## Case C: a locale that /usr/share/i18n/SUPPORTED lists without a codeset suffix

Most locales are listed in `/usr/share/i18n/SUPPORTED` with the codeset spelled out in the name
(e.g. `ja_JP.UTF-8 UTF-8`, alongside `ja_JP.EUC-JP EUC-JP`), but a locale with only ever one
encoding is listed under the plain name instead — there is no `aa_ER.UTF-8` line anywhere in the
file, only `aa_ER UTF-8`. This case checks that such a locale is still accepted.

```sh
LOCALE=aa_ER sh /mnt/f/install.sh; echo "exit status: $?"
```

Expected: exit status 0, and `aa_er.utf8` present in `locale -a`.
