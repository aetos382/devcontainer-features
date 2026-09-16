#!/bin/bash
# Ensures that include_security additionally replaces security.ubuntu.com with the requested
# mirror, and that apt-get still works against it.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "no reference to the default Ubuntu archive host remains" bash -c \
  "! grep -qrE 'https?://(archive|security)\.ubuntu\.com' /etc/apt/sources.list /etc/apt/sources.list.d/*.sources 2>/dev/null"
check "apt sources now point at the requested mirror" bash -c \
  "grep -qrF 'jp.archive.ubuntu.com' /etc/apt/sources.list /etc/apt/sources.list.d/*.sources 2>/dev/null"
check "apt-get update works against the new mirror" apt-get update -y

reportResults
