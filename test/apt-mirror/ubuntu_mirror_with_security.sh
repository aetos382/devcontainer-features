#!/bin/bash
# Ensures that, on Ubuntu, security_mirror replaces security.ubuntu.com in addition to what mirror
# replaces, and that apt-get still works afterward. Both option values carry a trailing slash,
# which the doubled-slash check below verifies was stripped: a server that tolerates '//' would let
# that regression reach apt-get update unnoticed. On a ports architecture (arm64 in CI), where the
# sources name ports.ubuntu.com instead, it ensures that the feature leaves them alone, as NOTES.md
# says; see _ubuntu_ports.sh for what that branch does not cover.
set -e

# shellcheck source=/dev/null
source 'dev-container-features-test-lib'
# shellcheck source=SCRIPTDIR/_ubuntu_ports.sh
source "$(dirname "${BASH_SOURCE[0]}")/_ubuntu_ports.sh"

if uses_ubuntu_ports; then
  # One host covers both options, since scenarios.json gives security_mirror the same URL as
  # mirror. Give them different hosts and this needs a second call.
  check_ubuntu_ports_untouched 'jp.archive.ubuntu.com'
else
  check 'no reference to the default Ubuntu hosts remains' bash -c \
    '! grep -qrE "https?://(archive|security)\.ubuntu\.com" /etc/apt/sources.list.d/'
  # shellcheck disable=SC2016 # expanded by the inner bash, not here
  check 'both archives now point at the requested mirror' bash -c \
    '[ "$(grep -c "^URIs: http://jp.archive.ubuntu.com/ubuntu/$" /etc/apt/sources.list.d/ubuntu.sources)" -eq 2 ]'
  check 'the trailing slash of the option values was stripped' bash -c \
    '! grep -qrF "jp.archive.ubuntu.com/ubuntu//" /etc/apt/sources.list.d/'
  check 'apt-get update works against the new mirror' apt-get update -y
fi

reportResults
