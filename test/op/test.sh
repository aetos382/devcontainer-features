#!/bin/bash
# Ensures that op is installed as a runnable binary on PATH with the default options, and that the
# feature left none of the apt-repository machinery (source list, keyring, debsig policy) in the
# image, which is the whole reason this feature downloads the release archive instead.
set -e

source dev-container-features-test-lib

check "op is on PATH" bash -c "command -v op"
check "op is installed at /usr/local/bin/op" test -x /usr/local/bin/op
check "op runs" op --version
check "op reports a 2.x version" bash -c "op --version | grep -qE '^2\.'"

check "no 1Password apt source list" bash -c "! test -e /etc/apt/sources.list.d/1password.list"
check "no 1Password apt keyring" bash -c "! test -e /usr/share/keyrings/1password-archive-keyring.gpg"
check "no debsig policy" bash -c "! test -d /etc/debsig/policies/AC2D62742012EA22"

# The imported signing key belongs to a throwaway GNUPGHOME under the build's temp directory.
check "signing key not left in root's keyring" bash -c "! gpg --list-keys 2>/dev/null | grep -q codesign@1password.com"

reportResults
