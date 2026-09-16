# Manual negative tests for `install.sh`

`install.sh` rejects several `mirror` situations that a passing `devcontainer features test`
scenario cannot express: the harness treats a failed build as a failed test, so a case that is
supposed to fail can't be a normal scenario. Run the cases below by hand whenever the validation in
`install.sh` changes.

## Setup

```sh
docker run --rm -v "$PWD/src/apt-mirror:/mnt/f:ro" mcr.microsoft.com/devcontainers/base:ubuntu sh
```

## Case A: a mirror value that isn't http:// or https://

```sh
MIRROR="ftp://example.com/ubuntu" sh /mnt/f/install.sh; echo "exit status: $?"
```

Expected: exit status 1, apt sources left untouched.

```
apt-mirror: 'mirror' must start with http:// or https:// (got 'ftp://example.com/ubuntu').
```

## Case B: a non-Ubuntu image

```sh
docker run --rm -v "$PWD/src/apt-mirror:/mnt/f:ro" debian:latest sh -c \
  'MIRROR="http://ftp.jp.debian.org/debian" sh /mnt/f/install.sh; echo "exit status: $?"'
```

Expected: exit status 1, apt sources left untouched.

```
apt-mirror: this feature only supports Ubuntu-based images (expected ID=ubuntu in /etc/os-release).
```

## Case C: a mirror that doesn't resolve

```sh
MIRROR="http://nonexistent.invalid.example/ubuntu" sh /mnt/f/install.sh; echo "exit status: $?"
```

Expected: exit status 1. Apt sources are rewritten (the failure is only caught at the verification
`apt-get update` afterward), so this is the one case worth re-running to confirm apt-get update's
`-o APT::Update::Error-Mode=any` is still doing its job -- without it, a failed fetch with an older
cached index to fall back on is treated as a warning and the script exits 0 instead.

```
apt-mirror: apt-get update failed after switching to 'http://nonexistent.invalid.example/ubuntu'; check that it is reachable and mirrors this distribution/release.
```
