#!/bin/bash
# Ensures that a CLAUDE_CONFIG_DIR set by the user via containerEnv is not overridden by the profile.d default.
#
# A command string passed to 'bash -c' is single-quoted whenever it holds no value of this script's
# own, so that its '$' reaches that nested shell unexpanded; SC2016 flags exactly that and is not a
# finding here.
# shellcheck disable=SC2016
set -e

# dev-container-features-test-lib is provided by the devcontainer CLI inside the test container, so
# ShellCheck has nothing to follow here. Suppressed per call site rather than for the whole
# directory, to keep a mistyped path to a script that does live in the repository detectable.
# shellcheck source=/dev/null
source 'dev-container-features-test-lib'

check 'CLAUDE_CONFIG_DIR keeps user value in login shell' bash -c '[ "$(bash -lc "printenv CLAUDE_CONFIG_DIR")" = "/tmp/claude-custom" ]'

# Proves profile.d is actually loaded and its guard fires in this container: if CLAUDE_CONFIG_DIR
# is stripped before the login shell starts, profile.d must fall back to the default. Without this,
# the check above cannot tell "profile.d preserved the value" apart from "profile.d never ran".
check 'CLAUDE_CONFIG_DIR falls back to default when unset' bash -c '[ "$(env -u CLAUDE_CONFIG_DIR bash -lc "printenv CLAUDE_CONFIG_DIR")" = "/var/lib/claude-code" ]'

# Double-quoted rather than single-quoted like the checks above: the message this greps for contains
# single quotes of its own, which a single-quoted string cannot hold.
check 'post-create warns and exits 0 because CLAUDE_CONFIG_DIR points elsewhere' bash -c "
  out=\$(/usr/local/share/claude-code/post-create.sh 2>&1)
  status=\$?
  [ \"\$status\" -eq 0 ] && echo \"\$out\" | grep -q \"not '/var/lib/claude-code'\"
"

reportResults
