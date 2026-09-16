#!/bin/bash
# Ensures the classic one-line format in /etc/apt/sources.list is rewritten, not just the deb822
# *.sources files the other scenarios exercise. The scenario pins Ubuntu 22.04 because deb822 only
# became the default in 24.04, making it the one image in this suite whose archive.ubuntu.com
# entries live in sources.list itself.
set -e

# shellcheck source=/dev/null
source 'dev-container-features-test-lib'

# Guards the premise of this scenario: if a future 22.04 image moved its entries to deb822 after
# all, every check below would still pass while testing nothing this scenario exists to test.
check 'sources.list is the file carrying the entries on this image' bash -c \
  'grep -qE "^deb " /etc/apt/sources.list'

check 'no reference to the default Ubuntu archive host remains' bash -c \
  '! grep -qrE "https?://archive\.ubuntu\.com" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null'
check 'sources.list now points at the requested mirror' bash -c \
  'grep -qF "jp.archive.ubuntu.com" /etc/apt/sources.list'
check 'security.ubuntu.com is left untouched' bash -c \
  'grep -qrE "https?://security\.ubuntu\.com" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null'
check 'no backup files are left behind once the mirror is verified' bash -c \
  '! ls /etc/apt/sources.list.apt-mirror.bak /etc/apt/sources.list.d/*.apt-mirror.bak >/dev/null 2>&1'
check 'apt-get update works against the new mirror' apt-get update -y

reportResults
