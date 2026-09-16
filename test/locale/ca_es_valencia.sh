#!/bin/bash
# Ensures a locale with an '@variant' component is generated correctly: the '.UTF-8' codeset must
# be inserted before '@variant' (ca_ES.UTF-8@valencia), not appended after it, or locale-gen
# mis-parses the name and silently fails to generate the locale.
#
# The command strings passed to 'bash -c' are single-quoted because they hold no value of this
# script's own; their '$' has to reach that nested shell unexpanded, which is what SC2016 warns
# about and is exactly what is wanted here.
# shellcheck disable=SC2016
set -e

# shellcheck source=/dev/null
source 'dev-container-features-test-lib'

check 'ca_ES.UTF-8@valencia is a generated locale' bash -c 'set -o pipefail; locale -a | grep -qFx "ca_ES.utf8@valencia"'
check 'update-locale recorded LANG' bash -c 'grep -qFx "LANG=ca_ES.UTF-8@valencia" "/etc/default/locale"'
check 'update-locale did not record LANGUAGE' bash -c '! grep -q "^LANGUAGE=" "/etc/default/locale"'
check 'update-locale did not record LC_ALL' bash -c '! grep -q "^LC_ALL=" "/etc/default/locale"'
check 'LANG is exported for a login shell' bash -c '[ "$(bash -lc "printenv LANG")" = "ca_ES.UTF-8@valencia" ]'
check 'LANGUAGE is not exported for a login shell' bash -c '[ -z "$(env -u "LANGUAGE" bash -lc "printenv LANGUAGE")" ]'
check 'LC_ALL is not exported for a login shell' bash -c '[ -z "$(env -u "LC_ALL" bash -lc "printenv LC_ALL")" ]'

reportResults
