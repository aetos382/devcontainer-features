#!/bin/bash
# Ensures that the version option installs exactly that version rather than the latest one, and
# that a non-root remote user can run the installed binary.
#
# The command strings passed to 'bash -c' are single-quoted because they hold no value of this
# script's own; their '$' has to reach that nested shell unexpanded, which is what SC2016 warns
# about and is exactly what is wanted here.
# shellcheck disable=SC2016
set -e

# dev-container-features-test-lib is provided by the devcontainer CLI inside the test container, so
# ShellCheck has nothing to follow here. Suppressed per call site rather than for the whole
# directory, to keep a mistyped path to a script that does live in the repository detectable.
# shellcheck source=/dev/null
source 'dev-container-features-test-lib'

# -x, not a substring match: '2.38.1' alone would also accept a hypothetical '12.38.10'. op --version
# prints the bare version and nothing else.
check 'op reports the pinned version' bash -c 'op --version | grep -qFx "2.38.1"'
check 'test runs as the non-root remote user' bash -c '[ "$(id -un)" = "vscode" ]'
check 'non-root user can run op' op --version

reportResults
