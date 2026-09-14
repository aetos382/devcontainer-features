#!/bin/bash
# Ensures that a CLAUDE_CONFIG_DIR set by the user via containerEnv is not overridden by the profile.d default.
set -e

source dev-container-features-test-lib

check "CLAUDE_CONFIG_DIR keeps user value in login shell" bash -c "[ \"\$(bash -lc 'printenv CLAUDE_CONFIG_DIR')\" = /tmp/claude-custom ]"

check "post-create warns and exits 0 because CLAUDE_CONFIG_DIR points elsewhere" bash -c "
  out=\$(/usr/local/share/claude-code-persistence/post-create.sh 2>&1)
  status=\$?
  [ \"\$status\" -eq 0 ] && echo \"\$out\" | grep -q \"not '/var/lib/claude-code-persistence'\"
"

reportResults
