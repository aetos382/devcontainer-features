# Manual negative tests for `install.sh`

`install.sh` installs `claude` only if gpg reports exactly one signature on `manifest.json`, and that signature is a *good* one from the pinned key, made with a key that is neither revoked nor expired; only if the binary hashes to the SHA256 that signed manifest lists; and only if the binary reports the version that was asked for. None of that can be covered by `devcontainer features test`: the harness treats a failed build as a failed test, so a scenario that is supposed to fail cannot be expressed. The automated tests therefore only ever exercise the success path.

Run the cases below by hand whenever the verification block in `install.sh` changes. Cases C, D, and E matter most: each is accepted if one specific check is removed (the fingerprint match, the single-signature requirement, and the `GOODSIG` requirement, respectively).

Everything runs in a throwaway container. Anthropic's hosts are contacted to fetch genuine artifacts during setup and, where noted, by the cases themselves; the rest run against a local HTTP server. The setup assumes an x86_64 host, since only the `linux-x64` binary is served.

To inspect what `install.sh` downloaded when a case fails unexpectedly, set `CLAUDE_CODE_KEEP_TMP=1` on the run; the temporary directory is then left behind and its path printed.

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
mkdir -p srv/real/linux-x64
curl -fsSL -o srv/real/manifest.json     "$REL/$V/manifest.json"
curl -fsSL -o srv/real/manifest.json.sig "$REL/$V/manifest.json.sig"
curl -fsSL -o srv/real/linux-x64/claude  "$REL/$V/linux-x64/claude"
curl -fsSL -o srv/real-key.asc https://downloads.claude.ai/keys/claude-code.asc
(cd srv && python3 -m http.server 8000 >/dev/null 2>&1 &)

# Restores the served release and key to the genuine ones. Every case starts with it.
reset_srv() {
  rm -rf "/tmp/srv/$V" && cp -r /tmp/srv/real "/tmp/srv/$V"
  cp -f /tmp/srv/real-key.asc /tmp/srv/claude-code.asc
}

# install.sh copies post-create.sh and entrypoint.sh from its own directory, so the patched copies
# have to live next to them.
cp -r /mnt/f /tmp/f

# install.sh hardcodes its endpoints, so each case runs a copy with the two URLs redirected at the
# local server. Nothing else about the script is changed.
patch_urls() {
  sed -e 's#https://downloads.claude.ai/claude-code-releases#http://127.0.0.1:8000#' \
      -e 's#https://downloads.claude.ai/keys/claude-code.asc#http://127.0.0.1:8000/claude-code.asc#' \
      /mnt/f/install.sh
}
```

`_REMOTE_USER` has to be set for every run below, because `install.sh` refuses to run without it.

## Case 0: the unmodified release installs

Run this first. Every other case only expects exit status 1, which a broken setup (the server not running, `patch_urls` not matching) would also produce; this case proves the setup itself works.

```sh
reset_srv
patch_urls > /tmp/f/ok.sh
_REMOTE_USER=root VERSION=$V sh /tmp/f/ok.sh; echo "exit status: $?"
rm -f /usr/local/bin/claude
```

Expected: exit status 0.

```
claude-code: installed Claude Code 2.1.267 (linux-x64) at /usr/local/bin/claude
```

The binary is removed afterwards so that Case G can check that nothing was installed.

## Case A: tampered manifest under the genuine signature

The most basic attack: change what the manifest says and keep its signature.

```sh
reset_srv
sed -i 's/"version"/"versioN"/' "/tmp/srv/$V/manifest.json"
patch_urls > /tmp/f/a.sh
_REMOTE_USER=root VERSION=$V sh /tmp/f/a.sh; echo "exit status: $?"
```

Expected: exit status 1, and gpg's own diagnosis quoted through.

```
claude-code: signature verification failed for the 2.1.267 release manifest.
claude-code:   gpg: BAD signature from "Anthropic Claude Code Release Signing <security@anthropic.com>" [unknown]
```

## Case B: tampered binary under a genuine signed manifest

```sh
reset_srv
dd if=/dev/urandom of="/tmp/srv/$V/linux-x64/claude" bs=1 count=16 seek=1000 conv=notrunc status=none
patch_urls > /tmp/f/b.sh
_REMOTE_USER=root VERSION=$V sh /tmp/f/b.sh; echo "exit status: $?"
```

Expected: exit status 1. The manifest still verifies; this is the checksum check, and it is what makes signing the manifest cover the binary at all.

```
claude-code: checksum mismatch for the linux-x64 binary of 2.1.267.
claude-code: the signed manifest lists <...>, but the download hashes to <...>.
```

## Case C: a valid signature from a different key

The pinned fingerprint is **not** replaced here. The signature is good and its key is valid; only the fingerprint match rejects it. If this case installs `claude`, the fingerprint check has been lost.

```sh
reset_srv
export GNUPGHOME=/tmp/othergpg && mkdir -p "$GNUPGHOME" && chmod 700 "$GNUPGHOME"
gpg --batch --quiet --pinentry-mode loopback --passphrase '' \
  --quick-generate-key 'Other release signing <security@anthropic.com>' default default never
gpg --batch --yes --detach-sign --output "/tmp/srv/$V/manifest.json.sig" "/tmp/srv/$V/manifest.json"
gpg --batch --armor --export > /tmp/srv/claude-code.asc
unset GNUPGHOME
patch_urls > /tmp/f/c.sh
_REMOTE_USER=root VERSION=$V sh /tmp/f/c.sh; echo "exit status: $?"
```

Expected: exit status 1.

```
claude-code: signature verification failed for the 2.1.267 release manifest.
claude-code:   gpg: Good signature from "Other release signing <security@anthropic.com>" [unknown]
```

## Case D: an expired signature from the pinned key alongside a valid one from another key

A detached signature file can hold several signatures, and gpg reports each separately. The pinned key's expired signature supplies a `VALIDSIG` naming the pinned fingerprint, and the other key's signature supplies a `GOODSIG`, so checking those two lines independently accepts this. Only the single-signature requirement rejects it.

A throwaway key stands in for the pinned one, so its fingerprint replaces the pinned fingerprint for this case only.

```sh
reset_srv
export GNUPGHOME=/tmp/multigpg && mkdir -p "$GNUPGHOME" && chmod 700 "$GNUPGHOME"
gpg --batch --quiet --pinentry-mode loopback --passphrase '' \
  --quick-generate-key 'Pinned stand-in <pinned@example.com>' default default seconds=5
P="$(gpg --batch --with-colons --fingerprint pinned@example.com | awk -F: '/^fpr:/{print $10; exit}')"
gpg --batch --yes --local-user "$P" --detach-sign --output /tmp/p.sig "/tmp/srv/$V/manifest.json"
sleep 6
gpg --batch --quiet --pinentry-mode loopback --passphrase '' \
  --quick-generate-key 'Other <other@example.com>' default default never
X="$(gpg --batch --with-colons --fingerprint other@example.com | awk -F: '/^fpr:/{print $10; exit}')"
gpg --batch --yes --local-user "$X" --detach-sign --output /tmp/x.sig "/tmp/srv/$V/manifest.json"
cat /tmp/p.sig /tmp/x.sig > "/tmp/srv/$V/manifest.json.sig"
gpg --batch --armor --export > /tmp/srv/claude-code.asc
unset GNUPGHOME
patch_urls | sed "s/^SIGNING_KEY_FINGERPRINT=.*/SIGNING_KEY_FINGERPRINT='$P'/" > /tmp/f/d.sh
_REMOTE_USER=root VERSION=$V sh /tmp/f/d.sh; echo "exit status: $?"
```

Expected: exit status 1. gpg itself exits 0 here and reports both signatures; before the single-signature requirement was added, `install.sh` installed `claude` in this case.

```
claude-code: signature verification failed for the 2.1.267 release manifest.
claude-code:   gpg: Good signature from "Pinned stand-in <pinned@example.com>" [expired]
claude-code:   gpg: Good signature from "Other <other@example.com>" [unknown]
```

## Case E: good signature from an expired key

As in Case D, a throwaway key's fingerprint replaces the pinned one. Otherwise the run would fail on the fingerprint mismatch and prove nothing about expiry.

```sh
reset_srv
export GNUPGHOME=/tmp/fakegpg && mkdir -p "$GNUPGHOME" && chmod 700 "$GNUPGHOME"
gpg --batch --quiet --pinentry-mode loopback --passphrase '' \
  --quick-generate-key 'Fake release signing <security@anthropic.com>' default default seconds=3
FPR="$(gpg --batch --with-colons --fingerprint | awk -F: '/^fpr:/{print $10; exit}')"
gpg --batch --yes --detach-sign --output "/tmp/srv/$V/manifest.json.sig" "/tmp/srv/$V/manifest.json"
sleep 4
gpg --batch --armor --export > /tmp/srv/claude-code.asc
unset GNUPGHOME
patch_urls | sed "s/^SIGNING_KEY_FINGERPRINT=.*/SIGNING_KEY_FINGERPRINT='$FPR'/" > /tmp/f/e.sh
_REMOTE_USER=root VERSION=$V sh /tmp/f/e.sh; echo "exit status: $?"
```

Expected: exit status 1. Note what gpg says: the signature *is* good and `VALIDSIG` does name the pinned fingerprint. Only the absence of `GOODSIG` (gpg emits `EXPKEYSIG` instead) rejects this.

```
claude-code: signature verification failed for the 2.1.267 release manifest.
claude-code:   gpg: Good signature from "Fake release signing <security@anthropic.com>" [expired]
claude-code:   gpg: Note: This key has expired!
```

If this case ever installs `claude` successfully, the verification has regressed to accepting keys Anthropic has retired.

The revoked-key case (`REVKEYSIG`) is not scripted here: generating and importing a revocation certificate in batch mode proved unreliable. gpg's `doc/DETAILS` states that exactly one of `GOODSIG` / `BADSIG` / `EXPSIG` / `EXPKEYSIG` / `REVKEYSIG` / `ERRSIG` is emitted per signature, so requiring `GOODSIG` covers revocation by the same mechanism Case E demonstrates for expiry.

## Case F: the signing key cannot be fetched

```sh
reset_srv
patch_urls | sed 's#http://127.0.0.1:8000/claude-code.asc#http://127.0.0.1:9/claude-code.asc#' > /tmp/f/f.sh
_REMOTE_USER=root VERSION=$V sh /tmp/f/f.sh; echo "exit status: $?"
```

Expected: exit status 1, with curl's message followed by a line that names what failed. `curl -fs` is silent about the URL it gave up on, so without this the log would end at curl's one-liner.

```
curl: (7) Failed to connect to 127.0.0.1 port 9 after 0 ms: Could not connect to server
claude-code: failed to download Anthropic's release signing key from http://127.0.0.1:9/claude-code.asc (see curl's message above).
```

## Case G: a different, genuinely signed release served at the pinned version's URL

The manifest signature says nothing about which version the release is, because the version appears only in the URL. This is the case the post-download version check exists for. Nothing is tampered with: the genuine 2.1.267 release, with its genuine signature, is simply published as if it were 2.1.200.

```sh
reset_srv
rm -rf /tmp/srv/2.1.200 && cp -r /tmp/srv/real /tmp/srv/2.1.200
patch_urls > /tmp/f/g.sh
_REMOTE_USER=root VERSION=2.1.200 sh /tmp/f/g.sh; echo "exit status: $?"
ls /usr/local/bin/claude
```

Expected: exit status 1, and `ls` reports that `/usr/local/bin/claude` does not exist. The check runs before the install, so a mismatched binary never lands on PATH.

```
claude-code: the binary at http://127.0.0.1:8000/2.1.200/linux-x64/claude reports '2.1.267 (Claude Code)', not the expected 2.1.200.
claude-code: the manifest signature verified, so this is Anthropic serving a different release at that URL, not a tampered download.
```

## Case H: a release with no manifest signature

Releases before 2.1.89 are unsigned. Serving a manifest without its `.sig` must fail rather than silently skip the signature check.

```sh
reset_srv
rm -rf /tmp/srv/2.1.88 && mkdir -p /tmp/srv/2.1.88 && cp /tmp/srv/real/manifest.json /tmp/srv/2.1.88/
_REMOTE_USER=root VERSION=2.1.88 sh /tmp/f/g.sh; echo "exit status: $?"
```

Expected: exit status 1, with the 404 named as a hint rather than a diagnosis, since a network failure reaches the same line.

```
claude-code: failed to download the manifest signature from http://127.0.0.1:8000/2.1.88/manifest.json.sig (see curl's message above).
claude-code: if that was a 404, version '2.1.88' predates 2.1.89 and is unsigned; this feature requires a signed manifest.
```

## Cases that need no local server

These run from the host, against an image with the prerequisites baked in. Without them, `install.sh` would stop at the missing-prerequisites stage (and, with `--network none`, fail to install them) and prove nothing. The script is mounted rather than piped on stdin, so that nothing else in the container can consume it.

```sh
docker build -t claude-code-test-deps - <<'EOF'
FROM debian:latest
RUN apt-get update && apt-get install -y --no-install-recommends curl gnupg ca-certificates
EOF
```

An unreachable channel pointer. Expect `could not resolve the 'latest' channel`.

```sh
docker run --rm --network none -v "$PWD/src/claude-code:/mnt/f:ro" -e _REMOTE_USER=root \
  claude-code-test-deps sh /mnt/f/install.sh; echo "exit status: $?"
```

A malformed version. Expect `'foo' does not look like a Claude Code version.` The network is disabled to show that the check happens before any download.

```sh
docker run --rm --network none -v "$PWD/src/claude-code:/mnt/f:ro" -e _REMOTE_USER=root -e VERSION=foo \
  claude-code-test-deps sh /mnt/f/install.sh; echo "exit status: $?"
```

A version that does not exist. This one contacts Anthropic's hosts. Expect the 404 hint on `manifest.json`.

```sh
docker run --rm -v "$PWD/src/claude-code:/mnt/f:ro" -e _REMOTE_USER=root -e VERSION=99.99.99 \
  claude-code-test-deps sh /mnt/f/install.sh; echo "exit status: $?"
```

```sh
docker image rm claude-code-test-deps
```
