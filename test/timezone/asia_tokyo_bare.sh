#!/bin/bash
# Ensures a non-default timezone is applied correctly even when tzdata must be installed for it,
# unlike the other scenarios which run against an image that already ships tzdata.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "/etc/timezone contains the requested timezone" bash -c "[ \"\$(cat /etc/timezone)\" = Asia/Tokyo ]"
check "/etc/localtime points at the requested zoneinfo entry" bash -c "[ \"\$(readlink -f /etc/localtime)\" = /usr/share/zoneinfo/Asia/Tokyo ]"
check "date reports JST" bash -c "set -o pipefail; date +%Z | grep -qFx JST"

reportResults
