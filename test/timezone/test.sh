#!/bin/bash
# Ensures that the default timezone is applied to both /etc/localtime and /etc/timezone.
#
# The command strings passed to 'bash -c' are single-quoted because they hold no value of this
# script's own; their '$' has to reach that nested shell unexpanded, which is what SC2016 warns
# about and is exactly what is wanted here.
# shellcheck disable=SC2016
set -e

# shellcheck source=/dev/null
source 'dev-container-features-test-lib'

check '/etc/timezone contains the default timezone' bash -c '[ "$(cat "/etc/timezone")" = "Etc/UTC" ]'
check '/etc/localtime points at the default zoneinfo entry' bash -c '[ "$(readlink -f "/etc/localtime")" = "/usr/share/zoneinfo/Etc/UTC" ]'
check 'date reports UTC' bash -c 'set -o pipefail; date +%Z | grep -qFx "UTC"'

reportResults
