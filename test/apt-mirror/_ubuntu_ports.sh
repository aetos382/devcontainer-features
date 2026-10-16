#!/bin/bash
# Shared by the Ubuntu scenarios, which source it; not a scenario itself, since scenarios.json has
# no key for it. The leading underscore keeps it from reading like one.
#
# On a ports architecture, the feature has nothing it recognizes to rewrite, and NOTES.md promises
# that it leaves the sources alone with a warning. These checks cover the "leaves alone" half only:
# a scenario sees the container after the build, not the build output, so removing the warning
# would not fail them. The warning text is checked by Case E of negative-tests.md instead.

# Whether Ubuntu takes its packages from ports.ubuntu.com here. That is decided by the dpkg
# architecture -- every one but amd64 and i386 uses ports -- not by uname -m, which names arm64 as
# aarch64 and would send the other ports architectures down the amd64 branch.
uses_ubuntu_ports() {
  case "$(dpkg --print-architecture)" in
    amd64 | i386) return 1 ;;
    *) return 0 ;;
  esac
}

# Checks that the image's sources still name ports.ubuntu.com and nothing else: exactly the two
# URIs of the image's ubuntu.sources (the main and the security archive), with no other URIs line
# in any file the feature would rewrite. Counting both catches a rewrite of either one, whichever
# URL it was rewritten to.
# $1: host of the requested mirror(s)
# shellcheck disable=SC2016 # expanded by the inner bash, not here
check_ubuntu_ports_untouched() {
  check 'every apt source still points at ports.ubuntu.com' bash -c '
    set -o pipefail
    [ -f /etc/apt/sources.list.d/ubuntu.sources ] || exit 1
    [ "$(cat /etc/apt/sources.list.d/*.sources | grep -c "^URIs:")" -eq 2 ] &&
    [ "$(cat /etc/apt/sources.list.d/*.sources | grep -c "^URIs: http://ports\.ubuntu\.com/ubuntu-ports/$")" -eq 2 ]'
  check 'apt sources do not name the requested mirror' bash -c \
    '! grep -qrF "$1" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null' _ "$1"
  check 'apt sources are still parseable' apt-get indextargets
}
