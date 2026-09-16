#!/bin/bash
# Ensures that the volume is mounted, writable by the remote user, selected as CLAUDE_CONFIG_DIR by default,
# and that the post-create script is installed and warns appropriately when CLAUDE_CONFIG_DIR is unset.
#
# A command string passed to 'bash -c' is single-quoted whenever it holds no value of this script's
# own, so that its '$' reaches that nested shell unexpanded; SC2016 flags exactly that and is not a
# finding here. The checks that do pass a value in use double quotes instead.
# shellcheck disable=SC2016
set -e

# dev-container-features-test-lib is provided by the devcontainer CLI inside the test container, so
# ShellCheck has nothing to follow here. Suppressed per call site rather than for the whole
# directory, to keep a mistyped path to a script that does live in the repository detectable.
# shellcheck source=/dev/null
source 'dev-container-features-test-lib'

MOUNT_POINT='/var/lib/claude-code-persistence'

check 'mount point is a mount' grep -q " $MOUNT_POINT " '/proc/mounts'
check 'mount point is writable' test -w "$MOUNT_POINT"
check 'CLAUDE_CONFIG_DIR defaults to mount point' bash -c "[ \"\$(bash -lc 'printenv CLAUDE_CONFIG_DIR')\" = '$MOUNT_POINT' ]"
check 'post-create script is installed' test -x '/usr/local/share/claude-code-persistence/post-create.sh'

check 'post-create warns and exits 0 when CLAUDE_CONFIG_DIR is unset' bash -c '
  out=$(env -u CLAUDE_CONFIG_DIR /usr/local/share/claude-code-persistence/post-create.sh 2>&1)
  status=$?
  [ "$status" -eq 0 ] && echo "$out" | grep -q "CLAUDE_CONFIG_DIR is not set"
'

reportResults
