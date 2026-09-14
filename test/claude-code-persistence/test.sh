#!/bin/bash
# Ensures that the volume is mounted, writable by the remote user, and selected as CLAUDE_CONFIG_DIR by default.
set -e

source dev-container-features-test-lib

MOUNT_POINT=/var/lib/claude-code-persistence

check "mount point is a mount" grep -q " $MOUNT_POINT " /proc/mounts
check "mount point is writable" test -w "$MOUNT_POINT"
check "CLAUDE_CONFIG_DIR defaults to mount point" bash -c "[ \"\$(bash -lc 'printenv CLAUDE_CONFIG_DIR')\" = $MOUNT_POINT ]"
check "post-create script is installed" test -x /usr/local/share/claude-code-persistence/post-create.sh

reportResults
