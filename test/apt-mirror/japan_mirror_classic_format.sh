#!/bin/bash
# Ensures the classic one-line format in /etc/apt/sources.list is rewritten, not just the deb822
# *.sources files the other scenarios exercise. Every supported release ships deb822 by default, so
# the scenario's Dockerfile rewrites Ubuntu 24.04's sources into sources.list first.
set -e

# shellcheck source=/dev/null
source 'dev-container-features-test-lib'

# Guards the premise of this scenario: if the Dockerfile's conversion stopped taking effect (say, a
# base image update brought back a deb822 file alongside it), every check below could still pass
# while testing nothing this scenario exists to test.
check 'sources.list is the file carrying the entries on this image' bash -c \
  'grep -qE "^deb " /etc/apt/sources.list && ! grep -qrE "https?://" /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null'

check 'no reference to the default Ubuntu archive host remains' bash -c \
  '! grep -qrE "https?://archive\.ubuntu\.com" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null'
check 'sources.list now points at the requested mirror' bash -c \
  'grep -qF "jp.archive.ubuntu.com" /etc/apt/sources.list'
check 'security.ubuntu.com is left untouched' bash -c \
  'grep -qrE "https?://security\.ubuntu\.com" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null'
check 'apt-get update works against the new mirror' apt-get update -y

reportResults
