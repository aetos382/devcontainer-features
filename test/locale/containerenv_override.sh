#!/bin/bash
# Ensures that the feature's locale option overrides a LANG value set through containerEnv,
# matching the deliberate precedence documented in NOTES.md.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "LANG for a login shell is the feature's locale, not containerEnv's" bash -c "[ \"\$(bash -lc 'printenv LANG')\" = ja_JP.UTF-8 ]"

reportResults
