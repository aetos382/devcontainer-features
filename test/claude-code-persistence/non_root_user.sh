#!/bin/bash
# Ensures that a non-root remote user owns the volume without sudo, via ownership seeded at build time.
set -e

source dev-container-features-test-lib

MOUNT_POINT=/var/lib/claude-code-persistence

check "running as vscode" bash -c '[ "$(id -un)" = vscode ]'
check "mount point is owned by vscode" bash -c "[ \"\$(stat -c %U $MOUNT_POINT)\" = vscode ]"
check "mount point is writable" bash -c "touch $MOUNT_POINT/.write-test && rm $MOUNT_POINT/.write-test"
check "CLAUDE_CONFIG_DIR defaults to mount point" bash -c "[ \"\$(bash -lc 'printenv CLAUDE_CONFIG_DIR')\" = $MOUNT_POINT ]"

# Simulates ownership left stale by a UID change (updateRemoteUserUID) and ensures the entrypoint restores it recursively.
sudo chown -R root:root "$MOUNT_POINT"
sudo touch "$MOUNT_POINT/.stale"
sudo /usr/local/share/claude-code-persistence/entrypoint.sh
check "entrypoint restores mount point ownership" bash -c "[ \"\$(stat -c %U $MOUNT_POINT)\" = vscode ]"
check "entrypoint restores ownership of volume contents" bash -c "[ \"\$(stat -c %U $MOUNT_POINT/.stale)\" = vscode ]"
check "entrypoint keeps mode 700" bash -c "[ \"\$(stat -c %a $MOUNT_POINT)\" = 700 ]"
rm -f "$MOUNT_POINT/.stale"

# Simulates ownership stuck as root (e.g. the entrypoint did not run as root) and ensures post-create.sh's sudo fallback restores writability.
sudo chown root:root "$MOUNT_POINT"
/usr/local/share/claude-code-persistence/post-create.sh
check "post-create sudo fallback restores ownership" bash -c "[ \"\$(stat -c %U $MOUNT_POINT)\" = vscode ]"
check "post-create sudo fallback restores mode 700" bash -c "[ \"\$(stat -c %a $MOUNT_POINT)\" = 700 ]"

reportResults
