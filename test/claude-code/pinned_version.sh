#!/bin/bash
# Ensures that the version option installs exactly that version rather than the channel's newest one,
# and that a leading 'v' (scenarios.json passes 'v2.1.267') is accepted and stripped.
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

# Anchored at both ends of the version field rather than matched as a substring: '2.1.267' alone
# would also accept a hypothetical '12.1.2670'. 'claude --version' prints the version followed by
# ' (Claude Code)', so the trailing anchor is the space, not end of line.
check 'claude reports the pinned version' bash -c 'HOME="$(mktemp -d)" claude --version | grep -qE "^2\.1\.267( |$)"'

reportResults
