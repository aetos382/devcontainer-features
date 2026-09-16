# Manual negative tests for `install.sh`

`install.sh` installs `claude` only if gpg reports a *good* signature on `manifest.json` from the
pinned key, made with a key that is neither revoked nor expired; only if the binary hashes to the
SHA256 that signed manifest lists; and only if the binary reports the version that was asked for.
None of that can be covered by `devcontainer features test`: the harness treats a failed build as a
failed test, so a scenario that is supposed to fail cannot be expressed. The automated tests
therefore only ever exercise the success path.

Run the cases below by hand whenever the verification block in `install.sh` changes. Case B is the
one that matters most: it is the case a `VALIDSIG`-only check would wrongly accept.

Everything runs in a throwaway container against a local HTTP server. Anthropic's hosts are contacted
once, to fetch a genuine manifest, signature, binary, and key.

## Setup

```sh
docker run --rm -it -v "$PWD/src/claude-code:/mnt/f:ro" debian:latest bash
```

Inside the container:

```sh
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  curl gnupg python3 ca-certificates
cd /tmp
V=2.1.267
REL=https://downloads.claude.ai/claude-code-releases
mkdir -p "srv/$V/linux-x64"
curl -fsSL -o "srv/$V/manifest.json"     "$REL/$V/manifest.json"
curl -fsSL -o "srv/$V/manifest.json.sig" "$REL/$V/manifest.json.sig"
curl -fsSL -o "srv/$V/linux-x64/claude"  "$REL/$V/linux-x64/claude"
curl -fsSL -o srv/claude-code.asc https://downloads.claude.ai/keys/claude-code.asc
cp -r "srv/$V" srv/real          # pristine copy, for restoring between cases
(cd srv && python3 -m http.server 8000 >/dev/null 2>&1 &)

# install.sh hardcodes its endpoints, so each case runs a copy with the two URLs redirected at the
# local server. Nothing else about the script is changed.
patch_urls() {
  sed -e 's#https://downloads.claude.ai/claude-code-releases#http://127.0.0.1:8000#' \
      -e 's#https://downloads.claude.ai/keys/claude-code.asc#http://127.0.0.1:8000/claude-code.asc#' \
      /mnt/f/install.sh
}
```

`_REMOTE_USER` has to be set for every run below, because `install.sh` refuses to run without it.

## Case A: tampered binary under a genuine signed manifest

```sh
cp -f /tmp/srv/real/linux-x64/claude "/tmp/srv/$V/linux-x64/claude"
dd if=/dev/urandom of="/tmp/srv/$V/linux-x64/claude" bs=1 count=16 seek=1000 conv=notrunc status=none
cd /tmp && patch_urls > a.sh
_REMOTE_USER=root VERSION=$V sh a.sh; echo "exit status: $?"
```

Expected: exit status 1. The manifest still verifies — this is the checksum check, not the signature
check, and it is what makes signing the manifest cover the binary at all.

```
claude-code: checksum mismatch for the linux-x64 binary of 2.1.267.
claude-code: the signed manifest lists <...>, but the download hashes to <...>.
```

## Case B: good signature from an expired key

A throwaway key cannot have Anthropic's fingerprint, so the pinned fingerprint is replaced with the
throwaway key's for this case only. Otherwise the run would fail on the fingerprint mismatch and
prove nothing about expiry.

```sh
cp -f /tmp/srv/real/linux-x64/claude "/tmp/srv/$V/linux-x64/claude"
export GNUPGHOME=/tmp/fakegpg && mkdir -p "$GNUPGHOME" && chmod 700 "$GNUPGHOME"
gpg --batch --quiet --passphrase '' \
  --quick-generate-key 'Fake release signing <security@anthropic.com>' default default seconds=3
FPR="$(gpg --batch --with-colons --fingerprint | awk -F: '/^fpr:/{print $10; exit}')"

cd "/tmp/srv/$V"
gpg --batch --yes --detach-sign --output manifest.json.sig manifest.json  # signed while still valid
sleep 4                                                                   # ... and now it is not
gpg --batch --armor --export > /tmp/srv/claude-code.asc

cd /tmp && unset GNUPGHOME
patch_urls | sed "s/^SIGNING_KEY_FINGERPRINT=.*/SIGNING_KEY_FINGERPRINT='$FPR'/" > b.sh
_REMOTE_USER=root VERSION=$V sh b.sh; echo "exit status: $?"
```

Expected: exit status 1. Note what gpg says — the signature *is* good and `VALIDSIG` does name the
pinned fingerprint. Only the absence of `GOODSIG` (gpg emits `EXPKEYSIG` instead) rejects this.

```
claude-code: signature verification failed for the 2.1.267 release manifest.
claude-code:   gpg: Good signature from "Fake release signing <security@anthropic.com>" [expired]
claude-code:   gpg: Note: This key has expired!
```

If this case ever installs `claude` successfully, the verification has regressed to accepting keys
Anthropic has retired.

The revoked-key case (`REVKEYSIG`) is not scripted here: generating and importing a revocation
certificate in batch mode proved unreliable. gpg's `doc/DETAILS` states that exactly one of
`GOODSIG` / `BADSIG` / `EXPSIG` / `EXPKEYSIG` / `REVKEYSIG` / `ERRSIG` is emitted per signature, so
requiring `GOODSIG` covers revocation by the same mechanism Case B demonstrates for expiry.

## Case C: the signing key cannot be fetched

```sh
cd /tmp
patch_urls | sed 's#http://127.0.0.1:8000/claude-code.asc#http://127.0.0.1:9/claude-code.asc#' > c.sh
_REMOTE_USER=root VERSION=$V sh c.sh; echo "exit status: $?"
```

Expected: exit status 1, with curl's message followed by a line that names what failed. `curl -fs` is
silent about the URL it gave up on, so without this the log would end at curl's one-liner.

```
curl: (7) Failed to connect to 127.0.0.1 port 9 after 0 ms: Could not connect to server
claude-code: failed to download Anthropic's release signing key from http://127.0.0.1:9/claude-code.asc (see curl's message above).
```

## Case D: a different, genuinely signed release served at the pinned version's URL

The manifest signature says nothing about which version the release is, because the version appears
only in the URL. This is the case the post-download version check exists for. Nothing is tampered
with: a real 2.1.267 release, with its real signature, is simply published as if it were 2.1.200.

```sh
# Case B replaced the served key and signature with throwaway ones; put the genuine ones back.
curl -fsSL -o /tmp/srv/claude-code.asc https://downloads.claude.ai/keys/claude-code.asc
rm -rf "/tmp/srv/$V" && cp -r /tmp/srv/real "/tmp/srv/$V"
cp -r /tmp/srv/real /tmp/srv/2.1.200

cd /tmp && patch_urls > d.sh
_REMOTE_USER=root VERSION=2.1.200 sh d.sh; echo "exit status: $?"
```

Expected: exit status 1, and no `claude` at `/usr/local/bin/claude` — the check runs before the
install, so a mismatched binary never lands on PATH.

```
claude-code: the binary at http://127.0.0.1:8000/2.1.200/linux-x64/claude reports '2.1.267 (Claude Code)', not the expected 2.1.200.
claude-code: the manifest signature verified, so this is Anthropic serving a different release at that URL, not a tampered download.
```

## Case E: a release with no manifest signature

Releases before 2.1.89 are unsigned. Serving a manifest without its `.sig` must fail rather than
silently skip the signature check.

```sh
mkdir -p /tmp/srv/2.1.88 && cp /tmp/srv/real/manifest.json /tmp/srv/2.1.88/
cd /tmp && _REMOTE_USER=root VERSION=2.1.88 sh d.sh; echo "exit status: $?"
```

Expected: exit status 1, with the 404 named as a hint rather than a diagnosis, since a network
failure reaches the same line.

```
claude-code: failed to download the manifest signature from http://127.0.0.1:8000/2.1.88/manifest.json.sig (see curl's message above).
claude-code: if that was a 404, version '2.1.88' predates 2.1.89 and is unsigned; this feature requires a signed manifest.
```

## Cases that need no local server

An unreachable channel pointer. Expect `could not resolve the 'latest' channel`. The prerequisites
have to be baked in first: with `--network none` on a bare image, `install.sh` exits at the
missing-prerequisites stage instead and proves nothing.

```sh
docker build -t claude-code-test-deps - <<'EOF'
FROM debian:latest
RUN apt-get update && apt-get install -y --no-install-recommends curl gnupg ca-certificates
EOF
docker run --rm -i --network none -e _REMOTE_USER=root claude-code-test-deps \
  sh -s < src/claude-code/install.sh; echo "exit status: $?"
docker image rm claude-code-test-deps
```

A version that does not exist. Expect the 404 hint on `manifest.json`.

```sh
docker run --rm -i -e _REMOTE_USER=root -e VERSION=99.99.99 debian:latest \
  sh -c 'apt-get update -qq && apt-get install -y -qq --no-install-recommends curl gnupg ca-certificates >/dev/null && sh -s' \
  < src/claude-code/install.sh; echo "exit status: $?"
```
