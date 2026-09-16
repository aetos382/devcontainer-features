#!/bin/bash
# Ensures that a non-default timezone option is applied instead of the default.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "/etc/timezone contains the requested timezone" bash -c "[ \"\$(cat /etc/timezone)\" = Asia/Tokyo ]"
check "/etc/localtime points at the requested zoneinfo entry" bash -c "[ \"\$(readlink -f /etc/localtime)\" = /usr/share/zoneinfo/Asia/Tokyo ]"
check "date reports JST" bash -c "date +%Z | grep -qFx JST"

reportResults
