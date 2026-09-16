# Manual negative tests for `install.sh`

`install.sh` rejects several situations that a passing `devcontainer features test` scenario cannot express: the harness treats a failed build as a failed test, so a case that is supposed to fail can't be a normal scenario.
Run the cases below by hand from the repository root whenever the validation in `install.sh` changes.
Each case is self-contained, so no shared setup step is needed.

## Case A: a mirror value that isn't http:// or https://

```sh
docker run --rm -v "$PWD/src/apt-mirror:/mnt/f:ro" mcr.microsoft.com/devcontainers/base:ubuntu sh -c \
  'MIRROR="ftp://example.com/ubuntu" sh /mnt/f/install.sh; echo "exit status: $?"'
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
docker run --rm -v "$PWD/src/apt-mirror:/mnt/f:ro" mcr.microsoft.com/devcontainers/base:ubuntu sh -c \
  'MIRROR="http://nonexistent.invalid.example/ubuntu" sh /mnt/f/install.sh; echo "exit status: $?"'
```

Expected: exit status 1. The rewritten apt sources are not restored: a failing feature fails the whole image build, so nothing is left to use them.
This is the one case worth re-running to confirm `apt-get update`'s `-o APT::Update::Error-Mode=any` is still doing its job: without it, a failed fetch that still has an older cached index to fall back on is reported as a warning and the script would exit 0 instead.

```
apt-mirror: apt-get update failed after switching to 'http://nonexistent.invalid.example/ubuntu'. Check that the mirror is reachable and mirrors this distribution/release.
```

## Case D: run as a non-root user

```sh
docker run --rm --user 1000 -v "$PWD/src/apt-mirror:/mnt/f:ro" mcr.microsoft.com/devcontainers/base:ubuntu sh -c \
  'MIRROR="http://jp.archive.ubuntu.com/ubuntu" sh /mnt/f/install.sh; echo "exit status: $?"'
```

Expected: exit status 1, apt sources left untouched.

```
apt-mirror: install.sh must be run as root.
```

## Case E: no default Ubuntu sources to rewrite

This is what an image already pointed at another mirror, or an arm64 image using `ports.ubuntu.com`, looks like to the feature.

```sh
docker run --rm -v "$PWD/src/apt-mirror:/mnt/f:ro" mcr.microsoft.com/devcontainers/base:ubuntu sh -c \
  'rm -f /etc/apt/sources.list /etc/apt/sources.list.d/*.sources /etc/apt/sources.list.d/*.list;
   MIRROR="http://jp.archive.ubuntu.com/ubuntu" sh /mnt/f/install.sh; echo "exit status: $?"'
```

Expected: exit status 0 with a warning, so that an image the feature doesn't recognize does not break the build.

```
apt-mirror: no default Ubuntu apt sources found in /etc/apt/sources.list or /etc/apt/sources.list.d/; leaving apt sources unchanged.
```
