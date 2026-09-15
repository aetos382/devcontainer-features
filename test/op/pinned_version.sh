#!/bin/bash
# Ensures that the version option installs exactly that version rather than the latest one, and
# that a non-root remote user can run the installed binary.
set -e

source dev-container-features-test-lib

check "op reports the pinned version" bash -c "op --version | grep -qF 2.38.1"
check "test runs as the non-root remote user" bash -c "[ \"\$(id -un)\" = vscode ]"
check "non-root user can run op" op --version

reportResults
