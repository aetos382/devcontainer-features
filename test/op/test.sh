#!/bin/bash
# Ensures that op is installed with the default options as a runnable binary on PATH, at the
# documented path with the documented ownership, that it is not under a package manager's control
# (which is the whole reason this feature downloads the release archive), and that 1Password's
# signing key was not left behind in the keyring of the user that installed it.
#
# The failure paths of the signature verification are not covered here and cannot be: the harness
# treats a failed build as a failed test. See negative-tests.md.
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

check 'op is on PATH' bash -c 'command -v "op"'
check 'op is installed at /usr/local/bin/op' test -x '/usr/local/bin/op'
check 'op runs' op --version
# 2.x is not an assumption about op's future, it is what install.sh is wired to: the distribution
# path (op2) and the update channel (CLI2) in its URLs are both specific to version 2, so 'latest'
# resolves to 2.x by construction and a hand-pinned 3.x would 404 during the build rather than reach
# this test. If op 3 ships, this check going red is the signal that those URLs need revisiting.
check 'op reports a 2.x version' bash -c 'op --version | grep -qE "^2\."'

# The README promises that apt-get upgrade cannot move this binary. That holds only while op comes
# from the release archive rather than 1Password's apt repository, which would place it under
# /usr/bin and hand its version to apt.
check 'op is not managed by a package manager' bash -c 'command -v "dpkg" >/dev/null && ! dpkg -S "/usr/local/bin/op" >/dev/null 2>&1'

check 'op is owned by root, mode 755' bash -c '[ "$(stat -c "%U %G %a" "/usr/local/bin/op")" = "root root 755" ]'

# install.sh runs as root with GNUPGHOME pointed at a throwaway directory, so root's keyring is the
# one that could have been polluted. Skipped when the test runs as a non-root remote user: that
# user's keyring was never a candidate, and asserting on it would pass without proving anything.
# command -v gpg comes first because the negation on its own is also satisfied by gpg being absent.
if [ "$(id -u)" -eq 0 ]; then
  check 'signing key not left in the root keyring' bash -c 'command -v "gpg" >/dev/null && ! gpg --list-keys 2>/dev/null | grep -q "codesign@1password.com"'
fi

reportResults
