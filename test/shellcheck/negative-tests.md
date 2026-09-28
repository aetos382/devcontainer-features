# Manual negative tests for `install.sh`

`install.sh` installs `shellcheck` only if the downloaded archive matches the sha256 digest pinned for this architecture, and fails on an unsupported architecture and on missing dependencies when `apt-get` is unavailable. None of that can be covered by `devcontainer features test`: the harness treats a failed build as a failed test, so a case that is supposed to fail cannot be expressed. The automated tests therefore only ever exercise the success path.

Run the cases below whenever the download, verification, architecture detection, or dependency handling in `install.sh` changes.

## Setup

Start a fresh container for each case: some cases modify it (Case D disables `apt-get`), and others install packages before they fail.

```sh
docker run --rm -it -v "$PWD/src/shellcheck:/mnt/f:ro" debian:13 sh
```

`install.sh` hardcodes its download URL, so Cases A and B run a copy with the URL pointed at a local directory through a `file://` URL. Nothing else about the script is changed.

## Case A: tampered archive

Requires an x86_64 host. The archive name is the one `install.sh` picks on x86_64.

```sh
VERSION="$(sed -n "s/^SHELLCHECK_VERSION='\(.*\)'$/\1/p" /mnt/f/install.sh)"
mkdir -p "/tmp/srv/${VERSION}"
printf 'tampered' > "/tmp/srv/${VERSION}/shellcheck-${VERSION}.linux.x86_64.tar.gz"
sed 's#https://github.com/koalaman/shellcheck/releases/download#file:///tmp/srv#' /mnt/f/install.sh > /tmp/patched.sh
sh /tmp/patched.sh; echo "exit status: $?"
```

Expected: exit status 1, both digests printed, and `/usr/local/bin/shellcheck` does not exist.

```
shellcheck: sha256 mismatch for shellcheck-
shellcheck: expected
shellcheck: got
```

## Case B: the archive cannot be downloaded

```sh
mkdir -p /tmp/srv
sed 's#https://github.com/koalaman/shellcheck/releases/download#file:///tmp/srv#' /mnt/f/install.sh > /tmp/patched.sh
sh /tmp/patched.sh; echo "exit status: $?"
```

Expected: exit status 1, with curl's own error followed by a line naming the URL that failed, and `/usr/local/bin/shellcheck` does not exist.

```
shellcheck: failed to download file:///tmp/srv/
```

## Case C: an unsupported architecture

Requires an x86_64 host. `linux32` (from util-linux) makes `uname -m` report `i686`, which exercises the architecture check without emulating another CPU.

```sh
linux32 sh /mnt/f/install.sh; echo "exit status: $?"
```

Expected: exit status 1, before any package is installed or anything is downloaded, and `/usr/local/bin/shellcheck` does not exist.

```
shellcheck: unsupported architecture 'i686'.
```

## Case D: a required tool is missing and apt-get is unavailable

```sh
mv /usr/bin/apt-get /usr/bin/apt-get.disabled
sh /mnt/f/install.sh; echo "exit status: $?"
```

Expected: exit status 1, and nothing is installed. `debian:13` lacks `curl`, so the message names at least `curl`.

```
shellcheck: the following are required but missing, and apt-get is unavailable to install them: curl
shellcheck: install them in your base image, or use a Debian/Ubuntu-based image.
```
