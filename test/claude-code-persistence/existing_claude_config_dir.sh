#!/bin/bash
# Ensures that a CLAUDE_CONFIG_DIR set by the user via containerEnv is not overridden by the profile.d default.
set -e

source dev-container-features-test-lib

check "CLAUDE_CONFIG_DIR keeps user value in login shell" bash -c "[ \"\$(bash -lc 'printenv CLAUDE_CONFIG_DIR')\" = /tmp/claude-custom ]"

reportResults
