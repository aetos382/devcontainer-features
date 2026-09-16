#!/bin/bash
# Ensures that a non-default locale option generates and exports that locale instead of en_US.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "ja_JP.UTF-8 is a generated locale" bash -c "locale -a | grep -qFx ja_JP.utf8"
check "update-locale recorded LANG" bash -c "grep -qFx 'LANG=ja_JP.UTF-8' /etc/default/locale"
check "LANG is exported for a login shell" bash -c "[ \"\$(bash -lc 'printenv LANG')\" = ja_JP.UTF-8 ]"

reportResults
