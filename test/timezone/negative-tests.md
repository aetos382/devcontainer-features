# Manual negative tests for `install.sh`

`install.sh` rejects a `timezone` option value that isn't a regular file inside
`/usr/share/zoneinfo/` — a directory (e.g. `Asia`), a non-zoneinfo file (e.g. `zone.tab`), or a
value that resolves outside the zoneinfo tree entirely (e.g. `../../../etc/passwd`). None of that
can be covered by `devcontainer features test`: the harness treats a failed build as a failed test,
so a scenario that is supposed to fail cannot be expressed. Run the cases below by hand whenever
the validation in `install.sh` changes.

## Setup

```sh
docker run --rm -v "$PWD/src/timezone:/mnt/f:ro" debian:latest sh
```

## Case A: a directory under zoneinfo, not a zone file

```sh
TIMEZONE=Asia sh /mnt/f/install.sh; echo "exit status: $?"
```

Expected: exit status 1, `/etc/localtime` left untouched.

```
timezone: timezone 'Asia' is not a valid zoneinfo entry.
```

## Case B: a path that traverses outside the zoneinfo tree

```sh
TIMEZONE="../../../etc/passwd" sh /mnt/f/install.sh; echo "exit status: $?"
```

Expected: exit status 1, `/etc/localtime` left untouched — not a symlink to `/etc/passwd`.

```
timezone: timezone '../../../etc/passwd' is not a valid zoneinfo entry.
```

## Case C: a name with no matching zoneinfo entry at all

```sh
TIMEZONE=Bogus/Zone sh /mnt/f/install.sh; echo "exit status: $?"
```

Expected: exit status 1, with the same message shape as cases A and B (tzdata gets installed first
since nothing at that path exists yet, but the entry still isn't found afterward).
