#!/bin/bash
# Ensures that, on Ubuntu, mirror replaces archive.ubuntu.com but, without security_mirror, leaves
# security.ubuntu.com pointed at Canonical's own server -- and that apt-get still works against
# the new mirror.
#
# This and the other scenarios fetch from real mirrors (jp.archive.ubuntu.com, ftp.jp.debian.org,
# security.debian.org), so an outage there fails CI. That is accepted: whether apt-get update succeeds against an actual mirror after the rewrite
# is the point of the checks, and a local stub would only prove the rewrite itself.
set -e

# shellcheck source=/dev/null
source 'dev-container-features-test-lib'

check 'no reference to the default Ubuntu archive host remains' bash -c \
  '! grep -qrE "https?://archive\.ubuntu\.com" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null'
check 'security.ubuntu.com is left untouched' bash -c \
  'grep -qrE "https?://security\.ubuntu\.com" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null'
check 'apt sources now point at the requested mirror' bash -c \
  'grep -qrF "jp.archive.ubuntu.com" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null'
# Names the deb822 file rather than grepping the directory, so that this scenario is on record as
# the one covering that format. Safe to pin now that the scenario pins the image too.
check 'the deb822 sources file is what was rewritten' bash -c \
  'grep -qF "jp.archive.ubuntu.com" /etc/apt/sources.list.d/ubuntu.sources'
# Runs before the apt-get update below, which would fetch the lists all over again.
# shellcheck disable=SC2016 # expanded by the inner bash, not here
check 'the package lists fetched to verify the mirror were removed' bash -c \
  '[ -z "$(ls -A /var/lib/apt/lists)" ]'
check 'apt-get update works against the new mirror' apt-get update -y

reportResults
