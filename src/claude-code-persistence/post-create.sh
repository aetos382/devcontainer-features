#!/bin/sh
set -u

FEATURE_ID=claude-code-persistence
MOUNT_POINT=/var/lib/claude-code-persistence

warn() {
    echo "$FEATURE_ID: warning: $*" >&2
}

if [ -z "${CLAUDE_CONFIG_DIR:-}" ]; then
    warn "CLAUDE_CONFIG_DIR is not set. /etc/profile.d may not have been loaded (e.g. \"userEnvProbe\": \"none\"). Claude Code settings will not be persisted."
    exit 0
fi

if [ "$CLAUDE_CONFIG_DIR" != "$MOUNT_POINT" ]; then
    warn "CLAUDE_CONFIG_DIR is set to '$CLAUDE_CONFIG_DIR', not '$MOUNT_POINT'. Claude Code settings will not be persisted by this feature."
    exit 0
fi

if ! grep -q " $MOUNT_POINT " /proc/mounts; then
    warn "$MOUNT_POINT is not a mount point. Claude Code settings will not be persisted."
    exit 0
fi

# Fallback for when the remote user did not exist at build time.
if [ ! -w "$MOUNT_POINT" ] && command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    sudo -n chown "$(id -u):$(id -g)" "$MOUNT_POINT" && sudo -n chmod 700 "$MOUNT_POINT"
fi

if [ ! -w "$MOUNT_POINT" ]; then
    warn "$MOUNT_POINT is not writable by $(id -un). Claude Code settings will not be persisted."
fi

exit 0
