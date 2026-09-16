#!/bin/bash
# Ensures that the default timezone is applied to both /etc/localtime and /etc/timezone.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "/etc/timezone contains the default timezone" bash -c "[ \"\$(cat /etc/timezone)\" = Etc/UTC ]"
check "/etc/localtime points at the default zoneinfo entry" bash -c "[ \"\$(readlink -f /etc/localtime)\" = /usr/share/zoneinfo/Etc/UTC ]"
check "date reports UTC" bash -c "date +%Z | grep -qFx UTC"

reportResults
