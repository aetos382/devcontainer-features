# Manual negative tests for `install.sh`

`install.sh` rejects several situations that a passing `devcontainer features test` scenario cannot express: the harness treats a failed build as a failed test, so a case that is supposed to fail can't be a normal scenario.
Run the cases below by hand from the repository root whenever the validation in `install.sh` changes.
Each case is self-contained, so no shared setup step is needed.

## Case A: a mirror value that isn't http:// or https://

```sh
docker run --rm -v "$PWD/src/apt-mirror:/mnt/f:ro" mcr.microsoft.com/devcontainers/base:3-ubuntu26.04 sh -c \
  'MIRROR="ftp://example.com/ubuntu" sh /mnt/f/install.sh; echo "exit status: $?"'
```

Expected: exit status 1, apt sources left untouched.

```
apt-mirror: 'mirror' must start with http:// or https:// (got 'ftp://example.com/ubuntu').
```

## Case A2: a mirror value containing whitespace

```sh
docker run --rm -v "$PWD/src/apt-mirror:/mnt/f:ro" mcr.microsoft.com/devcontainers/base:3-ubuntu26.04 sh -c \
  'MIRROR="http://jp.archive.ubuntu.com/ubuntu http://example.com/ubuntu" sh /mnt/f/install.sh; echo "exit status: $?"'
```

Expected: exit status 1, apt sources left untouched.

```
apt-mirror: 'mirror' must not contain whitespace or control characters (got 'http://jp.archive.ubuntu.com/ubuntu http://example.com/ubuntu').
```

## Case B: a non-Ubuntu image

```sh
docker run --rm -v "$PWD/src/apt-mirror:/mnt/f:ro" debian:13 sh -c \
  'MIRROR="http://ftp.jp.debian.org/debian" sh /mnt/f/install.sh; echo "exit status: $?"'
```

Expected: exit status 1, apt sources left untouched.

```
apt-mirror: this feature only supports Ubuntu-based images (expected ID=ubuntu in /etc/os-release).
```

## Case C: a mirror that doesn't resolve

```sh
docker run --rm -v "$PWD/src/apt-mirror:/mnt/f:ro" mcr.microsoft.com/devcontainers/base:3-ubuntu26.04 sh -c \
  'MIRROR="http://nonexistent.invalid.example/ubuntu" sh /mnt/f/install.sh; echo "exit status: $?"'
```

Expected: exit status 1. The rewritten apt sources are not restored: a failing feature fails the whole image build, so nothing is left to use them.
This is the one case worth re-running to confirm `apt-get update`'s `-o APT::Update::Error-Mode=any` is still doing its job: without it, a failed fetch that still has an older cached index to fall back on is reported as a warning and the script would exit 0 instead.

```
apt-mirror: apt-get update failed after switching to 'http://nonexistent.invalid.example/ubuntu'. Check that the mirror is reachable and mirrors this distribution/release.
```

## Case D: run as a non-root user

```sh
docker run --rm --user 1000 -v "$PWD/src/apt-mirror:/mnt/f:ro" mcr.microsoft.com/devcontainers/base:3-ubuntu26.04 sh -c \
  'MIRROR="http://jp.archive.ubuntu.com/ubuntu" sh /mnt/f/install.sh; echo "exit status: $?"'
```

Expected: exit status 1, apt sources left untouched.

```
apt-mirror: install.sh must be run as root.
```

## Case E: no default Ubuntu sources to rewrite

This is what an image already pointed at another mirror, or an arm64 image using `ports.ubuntu.com`, looks like to the feature.

```sh
docker run --rm -v "$PWD/src/apt-mirror:/mnt/f:ro" mcr.microsoft.com/devcontainers/base:3-ubuntu26.04 sh -c \
  'rm -f /etc/apt/sources.list.d/*.sources;
   MIRROR="http://jp.archive.ubuntu.com/ubuntu" sh /mnt/f/install.sh; echo "exit status: $?"'
```

Expected: exit status 0 with a warning, so that an image the feature doesn't recognize does not break the build.

```
apt-mirror: no default Ubuntu apt sources (archive.ubuntu.com, security.ubuntu.com) found in /etc/apt/sources.list.d/*.sources; leaving apt sources unchanged. 'http://jp.archive.ubuntu.com/ubuntu' is NOT in effect.
```

## Case F: an include_security value that isn't true or false

The CLI passes on whatever `devcontainer.json` says, so a typo such as `"True"` reaches `install.sh`. `mirror` is left empty here to show that the value is rejected even on the path that would otherwise change nothing.

```sh
docker run --rm -v "$PWD/src/apt-mirror:/mnt/f:ro" mcr.microsoft.com/devcontainers/base:3-ubuntu26.04 sh -c \
  'INCLUDE_SECURITY="True" sh /mnt/f/install.sh; echo "exit status: $?"'
```

Expected: exit status 1, apt sources left untouched.

```
apt-mirror: 'include_security' must be true or false (got 'True').
```

## Case G: one-line sources are left alone

Only the deb822 `*.sources` files are rewritten. This case moves the default entries into a one-line `sources.list`, which is how releases older than the supported ones ship them.

```sh
docker run --rm -v "$PWD/src/apt-mirror:/mnt/f:ro" mcr.microsoft.com/devcontainers/base:3-ubuntu26.04 sh -c \
  'rm -f /etc/apt/sources.list.d/*.sources;
   echo "deb http://archive.ubuntu.com/ubuntu/ resolute main" > /etc/apt/sources.list;
   MIRROR="http://jp.archive.ubuntu.com/ubuntu" sh /mnt/f/install.sh; echo "exit status: $?";
   cat /etc/apt/sources.list'
```

Expected: exit status 0 with the warning of Case E, and `sources.list` still naming `archive.ubuntu.com`.

## Case H: a second run on the same image

The feature runs twice on one image when the base image was prebuilt with it, or when another feature pulls it in through `dependsOn`. The duplicate test of `devcontainer features test` cannot cover this: it runs on every base image with a non-empty `mirror`, which the feature refuses on Debian.

Same mirror twice:

```sh
docker run --rm -v "$PWD/src/apt-mirror:/mnt/f:ro" mcr.microsoft.com/devcontainers/base:3-ubuntu26.04 sh -c \
  'MIRROR="http://jp.archive.ubuntu.com/ubuntu" sh /mnt/f/install.sh >/dev/null 2>&1; echo "first exit status: $?";
   MIRROR="http://jp.archive.ubuntu.com/ubuntu" sh /mnt/f/install.sh; echo "exit status: $?"'
```

Expected: exit status 0 from both runs, and no warning from the second. Its only output is on stdout:

```
apt-mirror: apt sources already point at http://jp.archive.ubuntu.com/ubuntu; nothing to change.
```

Another mirror on the second run:

```sh
docker run --rm -v "$PWD/src/apt-mirror:/mnt/f:ro" mcr.microsoft.com/devcontainers/base:3-ubuntu26.04 sh -c \
  'MIRROR="http://jp.archive.ubuntu.com/ubuntu" sh /mnt/f/install.sh >/dev/null 2>&1; echo "first exit status: $?";
   MIRROR="http://us.archive.ubuntu.com/ubuntu" sh /mnt/f/install.sh; echo "exit status: $?";
   grep -h "^URIs:" /etc/apt/sources.list.d/ubuntu.sources'
```

Expected: exit status 0 from both runs. The second run finds nothing it recognizes, warns, and leaves the first mirror in place.

```
apt-mirror: no default Ubuntu apt sources (archive.ubuntu.com, security.ubuntu.com) found in /etc/apt/sources.list.d/*.sources; leaving apt sources unchanged. 'http://us.archive.ubuntu.com/ubuntu' is NOT in effect.
```
