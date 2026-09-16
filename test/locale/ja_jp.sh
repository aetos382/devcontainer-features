#!/bin/bash
# Ensures that a non-default locale option generates and exports that locale instead of en_US.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "ja_JP.UTF-8 is a generated locale" bash -c "set -o pipefail; locale -a | grep -qFx ja_JP.utf8"
check "update-locale recorded LANG" bash -c "grep -qFx 'LANG=ja_JP.UTF-8' /etc/default/locale"
check "update-locale recorded LANGUAGE" bash -c "grep -qFx 'LANGUAGE=ja_JP:ja' /etc/default/locale"
check "update-locale recorded LC_ALL" bash -c "grep -qFx 'LC_ALL=ja_JP.UTF-8' /etc/default/locale"
check "LANG is exported for a login shell" bash -c "[ \"\$(bash -lc 'printenv LANG')\" = ja_JP.UTF-8 ]"
check "LANGUAGE is exported for a login shell" bash -c "[ \"\$(bash -lc 'printenv LANGUAGE')\" = ja_JP:ja ]"
check "LC_ALL is exported for a login shell" bash -c "[ \"\$(bash -lc 'printenv LC_ALL')\" = ja_JP.UTF-8 ]"

reportResults
