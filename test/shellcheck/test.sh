#!/bin/bash
# Ensures that shellcheck is installed with the default options as a runnable binary on PATH, at the
# documented path with the documented ownership, that it is the version install.sh pins, that it is
# not under a package manager's control, and that it actually reports findings on a script.
#
# The failure path of the digest verification is not covered here and cannot be: the harness treats
# a failed build as a failed test. See negative-tests.md.
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

check 'shellcheck is on PATH' bash -c 'command -v "shellcheck"'
check 'shellcheck is installed at /usr/local/bin/shellcheck' test -x '/usr/local/bin/shellcheck'
check 'shellcheck runs' shellcheck --version

# Must match SHELLCHECK_VERSION in install.sh. Bumping that without bumping this is caught here,
# which is the point: a version bump should be a deliberate change to both.
check 'shellcheck reports version 0.11.0' bash -c 'shellcheck --version | grep -qx "version: 0.11.0"'

# The binary comes from the release archive, not the distribution's package, whose version would be
# the distribution's choice rather than this feature's.
check 'shellcheck is not managed by a package manager' bash -c 'command -v "dpkg" >/dev/null && ! dpkg -S "/usr/local/bin/shellcheck" >/dev/null 2>&1'

check 'shellcheck is owned by root, mode 755' bash -c '[ "$(stat -c "%U %G %a" "/usr/local/bin/shellcheck")" = "root root 755" ]'

# --version alone would pass for a binary that starts but cannot analyse anything. An unquoted
# expansion is the textbook SC2086 finding; shellcheck exits 1 when it reports findings.
check 'shellcheck reports a finding' bash -c '
  out="$(printf "#!/bin/sh\necho \$1\n" | shellcheck -)"
  [ $? -eq 1 ] || exit 1
  printf "%s\n" "${out}" | grep -q "SC2086"
'
check 'shellcheck accepts a clean script' bash -c 'printf "#!/bin/sh\necho \"\$1\"\n" | shellcheck -'

reportResults
