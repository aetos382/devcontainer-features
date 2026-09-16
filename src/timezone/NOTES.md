## How it works

- Installs the `tzdata` package with `apt-get` if the requested zone is not already present under `/usr/share/zoneinfo`.
- Symlinks `/etc/localtime` to `/usr/share/zoneinfo/<timezone>` and writes `<timezone>` to `/etc/timezone`, the same two files `dpkg-reconfigure tzdata` updates.

## Limitations

- Only tested on Debian/Ubuntu-based images.
- `timezone` must be a name from the IANA Time Zone Database (e.g. `Asia/Tokyo`, `Etc/UTC`); the feature fails if no matching entry exists under `/usr/share/zoneinfo`.
- The `TZ` environment variable is not set. It is not needed for the system timezone to take effect, but if a process should use a different zone than the container's, set `TZ` yourself (for example through `containerEnv`).
