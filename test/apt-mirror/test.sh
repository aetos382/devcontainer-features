#!/bin/bash
# Ensures that leaving the mirror option empty makes no change to apt sources.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "apt sources still reference the default Ubuntu archive host" bash -c \
  "grep -qrE '(archive|security)\.ubuntu\.com' /etc/apt/sources.list /etc/apt/sources.list.d/*.sources 2>/dev/null"

reportResults
