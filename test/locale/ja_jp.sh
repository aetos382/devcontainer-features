#!/bin/bash
# Ensures that a non-default locale option generates and exports that locale instead of en_US.
#
# The command strings passed to 'bash -c' are single-quoted because they hold no value of this
# script's own; their '$' has to reach that nested shell unexpanded, which is what SC2016 warns
# about and is exactly what is wanted here.
# shellcheck disable=SC2016
set -e

# shellcheck source=/dev/null
source 'dev-container-features-test-lib'

check 'ja_JP.UTF-8 is a generated locale' bash -c 'set -o pipefail; locale -a | grep -qFx "ja_JP.utf8"'
check 'update-locale recorded LANG' bash -c 'grep -qFx "LANG=ja_JP.UTF-8" "/etc/default/locale"'
check 'update-locale did not record LANGUAGE' bash -c '! grep -q "^LANGUAGE=" "/etc/default/locale"'
check 'update-locale did not record LC_ALL' bash -c '! grep -q "^LC_ALL=" "/etc/default/locale"'
check 'LANG is exported for a login shell' bash -c '[ "$(bash -lc "printenv LANG")" = "ja_JP.UTF-8" ]'
check 'profile.d does not export LANGUAGE' bash -c '! grep -q "LANGUAGE" "/etc/profile.d/locale.sh"'
check 'profile.d does not export LC_ALL' bash -c '! grep -q "LC_ALL" "/etc/profile.d/locale.sh"'
# Covers a process such as an AI agent that wants English output while interactive shells use
# ja_JP: an LC_ALL it sets must survive a login shell reading /etc/profile.d.
check 'LC_ALL set by the caller survives a login shell' bash -c '[ "$(LC_ALL=C.UTF-8 bash -lc "printenv LC_ALL")" = "C.UTF-8" ]'
reportResults
