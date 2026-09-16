#!/bin/bash
# Ensures that the default locale is generated, recorded as the system default, and exported for
# interactive shells.
set -e

# dev-container-features-test-lib is provided by the devcontainer CLI inside the test container, so
# ShellCheck has nothing to follow here. Suppressed per call site rather than for the whole
# directory, to keep a mistyped path to a script that does live in the repository detectable.
# shellcheck source=/dev/null
source dev-container-features-test-lib

check "en_US.UTF-8 is a generated locale" bash -c "locale -a | grep -qFx en_US.utf8"
check "update-locale recorded LANG" bash -c "grep -qFx 'LANG=en_US.UTF-8' /etc/default/locale"
check "LANG is exported for a login shell" bash -c "[ \"\$(bash -lc 'printenv LANG')\" = en_US.UTF-8 ]"
check "LANGUAGE is exported for a login shell" bash -c "[ \"\$(bash -lc 'printenv LANGUAGE')\" = en_US.UTF-8 ]"
check "LC_ALL is exported for a login shell" bash -c "[ \"\$(bash -lc 'printenv LC_ALL')\" = en_US.UTF-8 ]"

reportResults
