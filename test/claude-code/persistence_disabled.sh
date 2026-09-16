#!/bin/bash
# Ensures that 'persistence: false' installs the CLI but wires up none of the persistence machinery:
# no CLAUDE_CONFIG_DIR default, and entrypoint and post-create both do nothing. The volume is still
# mounted, because a feature's 'mounts' cannot be made conditional on an option; what this checks is
# that the feature leaves it alone.
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

check 'claude runs and reports a version' bash -c 'HOME="$(mktemp -d)" claude --version | grep -qE "^[0-9]+\.[0-9]+\.[0-9]+"'

check 'profile.d snippet is not installed' bash -c '[ ! -e /etc/profile.d/claude-code.sh ]'
check 'persistence marker is not installed' bash -c '[ ! -e /usr/local/share/claude-code/persistence-enabled ]'
check 'CLAUDE_CONFIG_DIR is left unset in a login shell' bash -c '[ -z "$(bash -lc "printenv CLAUDE_CONFIG_DIR")" ]'

# Both are wired up unconditionally by devcontainer-feature.json, so the marker check inside them is
# the only thing keeping them quiet. Silence here is the whole point: any output would reach the user
# as a warning about persistence they did not ask for.
check 'post-create exits 0 and says nothing' bash -c '
  out=$(/usr/local/share/claude-code/post-create.sh 2>&1)
  status=$?
  [ "$status" -eq 0 ] && [ -z "$out" ]
'
check 'entrypoint exits 0 and says nothing' bash -c '
  out=$(sudo /usr/local/share/claude-code/entrypoint.sh 2>&1)
  status=$?
  [ "$status" -eq 0 ] && [ -z "$out" ]
'

reportResults
