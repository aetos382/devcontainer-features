#!/bin/bash
# Ensures that, on Ubuntu, security_mirror replaces security.ubuntu.com in addition to what mirror
# replaces, and that apt-get still works afterward. Both option values carry a trailing slash,
# which the doubled-slash check below verifies was stripped: a server that tolerates '//' would let
# that regression reach apt-get update unnoticed. On arm64, where the sources name ports.ubuntu.com
# instead, it ensures that the feature leaves them alone, as NOTES.md says.
set -e

# shellcheck source=/dev/null
source 'dev-container-features-test-lib'

if [ "$(uname -m)" = 'aarch64' ]; then
  check 'apt sources still point at ports.ubuntu.com' bash -c \
    'grep -qF "ports.ubuntu.com/ubuntu-ports" /etc/apt/sources.list.d/ubuntu.sources'
  check 'apt sources do not name the requested mirror' bash -c \
    '! grep -qrF "jp.archive.ubuntu.com" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null'
  check 'apt sources are still parseable' apt-get indextargets
  reportResults
  exit
fi

check 'no reference to the default Ubuntu hosts remains' bash -c \
  '! grep -qrE "https?://(archive|security)\.ubuntu\.com" /etc/apt/sources.list.d/'
# shellcheck disable=SC2016 # expanded by the inner bash, not here
check 'both archives now point at the requested mirror' bash -c \
  '[ "$(grep -c "^URIs: http://jp.archive.ubuntu.com/ubuntu/$" /etc/apt/sources.list.d/ubuntu.sources)" -eq 2 ]'
check 'the trailing slash of the option values was stripped' bash -c \
  '! grep -qrF "jp.archive.ubuntu.com/ubuntu//" /etc/apt/sources.list.d/'
check 'apt-get update works against the new mirror' apt-get update -y

reportResults
