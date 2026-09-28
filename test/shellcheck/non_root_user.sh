#!/bin/bash
# Ensures that a non-root remote user can run shellcheck: install.sh runs as root, so this is what
# catches an install path or mode that only root can use.
#
# The command strings passed to 'bash -c' are single-quoted because they hold no value of this
# script's own; their '$' has to reach that nested shell unexpanded, which is what SC2016 warns
# about and is exactly what is wanted here.
# shellcheck disable=SC2016
set -e

# dev-container-features-test-lib is provided by the devcontainer CLI inside the test container, so
# ShellCheck has nothing to follow here.
# shellcheck source=/dev/null
source 'dev-container-features-test-lib'

check 'running as vscode' bash -c '[ "$(id -un)" = "vscode" ]'
check 'non-root user can run shellcheck' shellcheck --version
check 'non-root user can lint a script' bash -c 'set -o pipefail; printf "#!/bin/sh\necho \"\$1\"\n" | shellcheck -'

reportResults
