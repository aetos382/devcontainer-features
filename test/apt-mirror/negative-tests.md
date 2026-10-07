# Manual tests for `install.sh`

`install.sh` has paths that a `devcontainer features test` scenario cannot express.

- Cases that are supposed to fail: the harness treats a failed build as a failed test.
- A second run on the same image: the harness's duplicate test picks the option values itself, and with two free-form URL options it has nothing to pick, so both of its runs would leave the options empty.

Run the cases below by hand from the repository root whenever the validation or the rewriting in `install.sh` changes.
Each case is self-contained, so no shared setup step is needed.

## Case A: a URL that isn't http:// or https://

```sh
docker run --rm -v "$PWD/src/apt-mirror:/mnt/f:ro" mcr.microsoft.com/devcontainers/base:3-ubuntu26.04 sh -c \
  'MIRROR="ftp://example.com/ubuntu" sh /mnt/f/install.sh; echo "exit status: $?"'
```

Expected: exit status 1, apt sources left untouched.

```
apt-mirror: 'mirror' must start with http:// or https:// (got 'ftp://example.com/ubuntu').
```

## Case A2: a URL containing whitespace

`security_mirror` is the option used here, and `mirror` is left empty, to show that each option is validated on its own.

```sh
docker run --rm -v "$PWD/src/apt-mirror:/mnt/f:ro" mcr.microsoft.com/devcontainers/base:3-ubuntu26.04 sh -c \
  'SECURITY_MIRROR="http://jp.archive.ubuntu.com/ubuntu http://example.com/ubuntu" sh /mnt/f/install.sh; echo "exit status: $?"'
```

Expected: exit status 1, apt sources left untouched.

```
apt-mirror: 'security_mirror' must not contain whitespace or control characters (got 'http://jp.archive.ubuntu.com/ubuntu http://example.com/ubuntu').
```

## Case B: a distribution other than Ubuntu and Debian

The case fakes the distribution by editing `/etc/os-release`, so that it needs no third image.

```sh
docker run --rm -v "$PWD/src/apt-mirror:/mnt/f:ro" mcr.microsoft.com/devcontainers/base:3-ubuntu26.04 sh -c \
  'sed -i "s/^ID=.*/ID=fedora/" /etc/os-release;
   MIRROR="http://example.com/fedora" sh /mnt/f/install.sh; echo "exit status: $?"'
```

Expected: exit status 1, apt sources left untouched.

```
apt-mirror: this feature only supports Ubuntu and Debian images (ID in /etc/os-release is 'fedora').
```

## Case C: a mirror that doesn't resolve

```sh
docker run --rm -v "$PWD/src/apt-mirror:/mnt/f:ro" mcr.microsoft.com/devcontainers/base:3-ubuntu26.04 sh -c \
  'MIRROR="http://nonexistent.invalid.example/ubuntu" sh /mnt/f/install.sh; echo "exit status: $?"'
```

Expected: exit status 1. The rewritten apt sources are not restored: a failing feature fails the whole image build, so nothing is left to use them.
This is the one case worth re-running to confirm `apt-get update`'s `-o APT::Update::Error-Mode=any` is still doing its job: without it, a failed fetch that still has an older cached index to fall back on is reported as a warning and the script would exit 0 instead.

```
apt-mirror: apt-get update failed after rewriting apt sources (mirror='http://nonexistent.invalid.example/ubuntu', security_mirror=''). Check that each is reachable and mirrors this distribution/release.
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

## Case E: no default sources to rewrite

This is what an image already pointed at another mirror, or an Ubuntu image for arm64 using `ports.ubuntu.com`, looks like to the feature.

```sh
docker run --rm -v "$PWD/src/apt-mirror:/mnt/f:ro" mcr.microsoft.com/devcontainers/base:3-ubuntu26.04 sh -c \
  'sed -i "s#//[a-z]*\.ubuntu\.com/ubuntu/#//ports.ubuntu.com/ubuntu-ports/#" /etc/apt/sources.list.d/ubuntu.sources;
   MIRROR="http://jp.archive.ubuntu.com/ubuntu" SECURITY_MIRROR="http://jp.archive.ubuntu.com/ubuntu" sh /mnt/f/install.sh; echo "exit status: $?";
   grep -h "^URIs:" /etc/apt/sources.list.d/ubuntu.sources'
```

Expected: exit status 0 with one warning per option, so that an image the feature doesn't recognize does not break the build. Both `URIs:` lines still name `ports.ubuntu.com/ubuntu-ports`.

```
apt-mirror: no apt source for archive.ubuntu.com/ubuntu found in /etc/apt/sources.list.d/*.sources; 'mirror' (http://jp.archive.ubuntu.com/ubuntu) is NOT in effect.
apt-mirror: no apt source for security.ubuntu.com/ubuntu found in /etc/apt/sources.list.d/*.sources; 'security_mirror' (http://jp.archive.ubuntu.com/ubuntu) is NOT in effect.
```

## Case F: one-line sources are left alone

Only the deb822 `*.sources` files are rewritten. This case moves the default entry into a one-line `sources.list`, which is how releases older than the supported ones ship them.

```sh
docker run --rm -v "$PWD/src/apt-mirror:/mnt/f:ro" mcr.microsoft.com/devcontainers/base:3-ubuntu26.04 sh -c \
  'rm -f /etc/apt/sources.list.d/*.sources;
   echo "deb http://archive.ubuntu.com/ubuntu/ resolute main" > /etc/apt/sources.list;
   MIRROR="http://jp.archive.ubuntu.com/ubuntu" sh /mnt/f/install.sh; echo "exit status: $?";
   cat /etc/apt/sources.list'
```

Expected: exit status 0 with the `mirror` warning of Case E, and `sources.list` still naming `archive.ubuntu.com`.

## Case G: a second run on the same image

The feature runs twice on one image when the base image was prebuilt with it, or when another feature pulls it in through `dependsOn`.

Same mirror twice:

```sh
docker run --rm -v "$PWD/src/apt-mirror:/mnt/f:ro" debian:13 sh -c \
  'MIRROR="http://ftp.jp.debian.org/debian" sh /mnt/f/install.sh >/dev/null 2>&1; echo "first exit status: $?";
   MIRROR="http://ftp.jp.debian.org/debian" sh /mnt/f/install.sh; echo "exit status: $?"'
```

Expected: exit status 0 from both runs, and no warning from the second. Its only output is on stdout:

```
apt-mirror: nothing to change in apt sources.
```

Another mirror on the second run, together with a `security_mirror` that the first run did not set:

```sh
docker run --rm -v "$PWD/src/apt-mirror:/mnt/f:ro" debian:13 sh -c \
  'MIRROR="http://ftp.jp.debian.org/debian" sh /mnt/f/install.sh >/dev/null 2>&1; echo "first exit status: $?";
   MIRROR="http://ftp.us.debian.org/debian" SECURITY_MIRROR="http://security.debian.org/debian-security" sh /mnt/f/install.sh; echo "exit status: $?";
   grep -h "^URIs:" /etc/apt/sources.list.d/debian.sources'
```

Expected: exit status 0 from both runs. The second run cannot switch the archive from one mirror to another: it warns and leaves the first mirror in place. The security archive still named its default, so it is rewritten.

```
apt-mirror: no apt source for deb.debian.org/debian found in /etc/apt/sources.list.d/*.sources; 'mirror' (http://ftp.us.debian.org/debian) is NOT in effect.
```

```
URIs: http://ftp.jp.debian.org/debian/
URIs: http://security.debian.org/debian-security/
```
