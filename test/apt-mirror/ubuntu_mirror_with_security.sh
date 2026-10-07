#!/bin/bash
# Ensures that, on Ubuntu, security_mirror replaces security.ubuntu.com in addition to what mirror
# replaces, and that apt-get still works afterward. Both option values carry a trailing slash,
# which the doubled-slash check below verifies was stripped: a server that tolerates '//' would let
# that regression reach apt-get update unnoticed.
set -e

# shellcheck source=/dev/null
source 'dev-container-features-test-lib'

check 'no reference to the default Ubuntu hosts remains' bash -c \
  '! grep -qrE "https?://(archive|security)\.ubuntu\.com" /etc/apt/sources.list.d/'
# shellcheck disable=SC2016 # expanded by the inner bash, not here
check 'both archives now point at the requested mirror' bash -c \
  '[ "$(grep -c "^URIs: http://jp.archive.ubuntu.com/ubuntu/$" /etc/apt/sources.list.d/ubuntu.sources)" -eq 2 ]'
check 'the trailing slash of the option values was stripped' bash -c \
  '! grep -qrF "jp.archive.ubuntu.com/ubuntu//" /etc/apt/sources.list.d/'
check 'apt-get update works against the new mirror' apt-get update -y

reportResults
