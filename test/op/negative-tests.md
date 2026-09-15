# Manual negative tests for `install.sh`

`install.sh` installs `op` only if gpg reports a *good* signature from the pinned key, made with a
key that is neither revoked nor expired, and only if the binary reports the version that was asked
for. None of that can be covered by `devcontainer features test`:
the harness treats a failed build as a failed test, so a scenario that is supposed to fail cannot be
expressed. The automated tests therefore only ever exercise the success path.

Run the cases below by hand whenever the verification block in `install.sh` changes. Case B is the
one that matters most: before the `GOODSIG` requirement was added, `install.sh` accepted a signature
from an expired key, and no bot review caught it.

Everything runs in a throwaway container against a local HTTP server. 1Password's hosts are contacted
once, to fetch a genuine archive and key.

## Setup

```sh
docker run --rm -it -v "$PWD/src/op:/mnt/f:ro" debian:latest bash
```

Inside the container:

```sh
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  curl unzip gnupg zip python3 ca-certificates
cd /tmp
curl -fsSL -o real.zip https://cache.agilebits.com/dist/1P/op2/pkg/v2.39.0/op_linux_amd64_v2.39.0.zip
mkdir -p srv/v2.39.0
curl -fsSL -o srv/1password.asc https://downloads.1password.com/linux/keys/1password.asc
(cd srv && python3 -m http.server 8000 >/dev/null 2>&1 &)

# install.sh hardcodes its endpoints, so each case runs a copy with the two URLs redirected at the
# local server. Nothing else about the script is changed.
patch_urls() {
  sed -e 's#https://cache.agilebits.com/dist/1P/op2/pkg#http://127.0.0.1:8000#' \
      -e 's#https://downloads.1password.com/linux/keys/1password.asc#http://127.0.0.1:8000/1password.asc#' \
      /mnt/f/install.sh
}
```

## Case A: tampered binary carrying the genuine signature

```sh
rm -rf work && mkdir work && cd work
unzip -q ../real.zip op op.sig
dd if=/dev/urandom of=op bs=1 count=16 seek=1000 conv=notrunc status=none
zip -q ../srv/v2.39.0/op_linux_amd64_v2.39.0.zip op op.sig
cd /tmp && patch_urls > a.sh
VERSION=2.39.0 sh a.sh; echo "exit status: $?"
```

Expected: exit status 1, and gpg's own diagnosis quoted through.

```
op: signature verification failed for op_linux_amd64_v2.39.0.zip.
op: expected a good signature from 1Password's code signing key 3FEF9748469ADBE15DA7CA80AC2D62742012EA22,
op: made with a key that is neither revoked nor expired. gpg reported:
op:   gpg: BAD signature from "Code signing for 1Password <codesign@1password.com>" [unknown]
```

## Case B: good signature from an expired key

A throwaway key cannot have 1Password's fingerprint, so the pinned fingerprint is replaced with the
throwaway key's for this case only. Otherwise the run would fail on the fingerprint mismatch and
prove nothing about expiry.

```sh
export GNUPGHOME=/tmp/fakegpg && mkdir -p "$GNUPGHOME" && chmod 700 "$GNUPGHOME"
gpg --batch --quiet --passphrase '' \
  --quick-generate-key 'Fake code signing <codesign@1password.com>' default default seconds=3
FPR="$(gpg --batch --with-colons --fingerprint | awk -F: '/^fpr:/{print $10; exit}')"

rm -rf work && mkdir work && cd work
unzip -q ../real.zip op
gpg --batch --yes --detach-sign --output op.sig op   # signed while the key is still valid
sleep 4                                              # ... and now it is not
gpg --batch --armor --export > /tmp/srv/1password.asc
rm -f ../srv/v2.39.0/op_linux_amd64_v2.39.0.zip
zip -q ../srv/v2.39.0/op_linux_amd64_v2.39.0.zip op op.sig

cd /tmp && unset GNUPGHOME
patch_urls | sed "s/^SIGNING_KEY_FINGERPRINT=.*/SIGNING_KEY_FINGERPRINT=$FPR/" > b.sh
VERSION=2.39.0 sh b.sh; echo "exit status: $?"
```

Expected: exit status 1. Note what gpg says — the signature *is* good and `VALIDSIG` does name the
pinned fingerprint. Only the absence of `GOODSIG` (gpg emits `EXPKEYSIG` instead) rejects this.

```
op: signature verification failed for op_linux_amd64_v2.39.0.zip.
op:   gpg: Good signature from "Fake code signing <codesign@1password.com>" [expired]
op:   gpg: Note: This key has expired!
```

If this case ever installs `op` successfully, the verification has regressed to accepting keys
1Password has retired.

The revoked-key case (`REVKEYSIG`) is not scripted here: generating and importing a revocation
certificate in batch mode proved unreliable. gpg's `doc/DETAILS` states that exactly one of
`GOODSIG` / `BADSIG` / `EXPSIG` / `EXPKEYSIG` / `REVKEYSIG` / `ERRSIG` is emitted per signature, so
requiring `GOODSIG` covers revocation by the same mechanism Case B demonstrates for expiry.

## Case C: the signing key cannot be fetched

```sh
patch_urls | sed 's#http://127.0.0.1:8000/1password.asc#http://127.0.0.1:9/1password.asc#' > c.sh
VERSION=2.39.0 sh c.sh; echo "exit status: $?"
```

Expected: exit status 1, with curl's message followed by a line that names what failed. `curl -fs` is
silent about the URL it gave up on, so without this the log would end at curl's one-liner.

```
curl: (7) Failed to connect to 127.0.0.1 port 9 after 0 ms: Could not connect to server
op: failed to download 1Password's code signing key from http://127.0.0.1:9/1password.asc (see curl's message above).
```

## Case D: a different, genuinely signed release served at the pinned version's URL

The signature says nothing about which version the binary is, so this is the case the version check
after installation exists for. Nothing is tampered with here: a real 2.39.0 archive, with its real
signature, is simply published as if it were 2.38.1.

```sh
# Case B replaced the served key with a throwaway one; put 1Password's back.
curl -fsSL -o /tmp/srv/1password.asc https://downloads.1password.com/linux/keys/1password.asc
mkdir -p /tmp/srv/v2.38.1
cp /tmp/real.zip /tmp/srv/v2.38.1/op_linux_amd64_v2.38.1.zip

cd /tmp && patch_urls > d.sh
VERSION=2.38.1 sh d.sh; echo "exit status: $?"
```

Expected: exit status 1, and no `op` at `/usr/local/bin/op` — the check runs before the install, so a
mismatched binary never lands on PATH.

```
op: op_linux_amd64_v2.38.1.zip contains 1Password CLI 2.39.0, not the requested 2.38.1.
op: the signature verified, so this is 1Password serving a different release at http://127.0.0.1:8000/v2.38.1/, not a tampered download.
```

There is no `latest` counterpart to run: the check is deliberately skipped there, and `latest` would
resolve through the unpatched update-check endpoint to a version this local server has no archive
for.

## Cases that need no local server

A version that exists but is not published for download. Expect the 404 hint, phrased as a hint
because network and TLS failures reach the same line.

```sh
VERSION=2.38.0 sh /mnt/f/install.sh; echo "exit status: $?"
```

An unreachable version check endpoint. Expect `could not get a version check response`. The
prerequisites have to be baked in first: with `--network none` on a bare image, `install.sh` exits at
the missing-prerequisites stage instead and proves nothing.

```sh
docker build -t op-test-deps - <<'EOF'
FROM debian:latest
RUN apt-get update && apt-get install -y --no-install-recommends curl unzip gnupg ca-certificates
EOF
docker run --rm -i --network none op-test-deps sh -s < src/op/install.sh; echo "exit status: $?"
docker image rm op-test-deps
```
