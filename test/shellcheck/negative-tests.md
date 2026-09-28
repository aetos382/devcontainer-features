# Manual negative tests for `install.sh`

`install.sh` installs `shellcheck` only if the downloaded archive matches the sha256 digest pinned
for this architecture. That cannot be covered by `devcontainer features test`: the harness treats a
failed build as a failed test, so a scenario that is supposed to fail cannot be expressed. The
automated tests therefore only ever exercise the success path.

Run the cases below by hand whenever the download or verification part of `install.sh` changes.

## Setup

```sh
docker run --rm -it -v "$PWD/src/shellcheck:/mnt/f:ro" debian:latest bash
```

Inside the container:

```sh
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  curl xz-utils python3 ca-certificates
cd /tmp
VERSION="$(sed -n "s/^SHELLCHECK_VERSION='\(.*\)'$/\1/p" /mnt/f/install.sh)"
ARCHIVE="shellcheck-${VERSION}.linux.$(uname -m).tar.xz"
curl -fsSL -o real.tar.xz "https://github.com/koalaman/shellcheck/releases/download/${VERSION}/${ARCHIVE}"
mkdir -p "srv/${VERSION}"
(cd srv && python3 -m http.server 8000 >/dev/null 2>&1 &)

# install.sh hardcodes its download URL, so each case runs a copy with it redirected at the local
# server. Nothing else about the script is changed.
patch_url() {
  sed 's#https://github.com/koalaman/shellcheck/releases/download#http://127.0.0.1:8000#' \
    /mnt/f/install.sh
}
```

## Case A: tampered archive

```sh
cp real.tar.xz "srv/${VERSION}/${ARCHIVE}"
printf 'x' >> "srv/${VERSION}/${ARCHIVE}"
patch_url > a.sh
sh a.sh; echo "exit status: $?"
```

Expected: exit status 1, both digests printed, and no `shellcheck` at `/usr/local/bin/shellcheck`.

```
sha256sum: WARNING: 1 computed checksum did NOT match
shellcheck: sha256 mismatch for shellcheck-v0.11.0.linux.x86_64.tar.xz.
shellcheck: expected 8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198,
shellcheck: got      <the tampered archive's digest>.
```

## Case B: the archive cannot be downloaded

```sh
rm -f "srv/${VERSION}/${ARCHIVE}"
sh a.sh; echo "exit status: $?"
```

Expected: exit status 1, with curl's 404 message followed by a line naming the URL that failed.

```
curl: (22) The requested URL returned error: 404
shellcheck: failed to download http://127.0.0.1:8000/v0.11.0/shellcheck-v0.11.0.linux.x86_64.tar.xz (see curl's message above).
```
