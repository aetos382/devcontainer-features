#!/bin/bash
# Ensures that the feature's locale option overrides a LANG value set through containerEnv,
# matching the deliberate precedence documented in NOTES.md.
#
# The command string passed to 'bash -c' is single-quoted because it holds no value of this
# script's own; its '$' has to reach that nested shell unexpanded, which is what SC2016 warns
# about and is exactly what is wanted here.
# shellcheck disable=SC2016
set -e

# shellcheck source=/dev/null
source 'dev-container-features-test-lib'

# The description is double-quoted rather than single-quoted: it contains apostrophes of its own,
# which a single-quoted string cannot hold.
check "LANG for a login shell is the feature's locale, not containerEnv's" bash -c '[ "$(bash -lc "printenv LANG")" = "ja_JP.UTF-8" ]'

reportResults
