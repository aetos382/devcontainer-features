#!/bin/sh
# Untested branches (see test/claude-code-persistence): "mount point is not a mount" (MOUNT_POINT is
# hardcoded, so simulating it needs an actual unmount) and "still not writable after the sudo fallback"
# (needs a container without passwordless sudo, or a temporary sudoers edit). Both were judged too
# heavy for the coverage gained; revisit if a lighter way to simulate them turns up.
set -u

FEATURE_ID=claude-code-persistence
MOUNT_POINT=/var/lib/claude-code-persistence

warn() {
  echo "$FEATURE_ID: warning: $*" >&2
}

err() {
  echo "$FEATURE_ID: error: $*" >&2
}

if [ -z "${CLAUDE_CONFIG_DIR:-}" ]; then
  warn "CLAUDE_CONFIG_DIR is not set. /etc/profile.d may not have been loaded (e.g. \"userEnvProbe\": \"none\", or the remote user's login shell is zsh, which does not read /etc/profile.d by default). Claude Code settings will not be persisted."
  exit 0
fi

if [ "${CLAUDE_CONFIG_DIR%/}" != "$MOUNT_POINT" ]; then
  warn "CLAUDE_CONFIG_DIR is set to '$CLAUDE_CONFIG_DIR', not '$MOUNT_POINT'. Claude Code settings will not be persisted by this feature."
  exit 0
fi

if ! grep -q " $MOUNT_POINT " /proc/mounts; then
  warn "$MOUNT_POINT is not a mount point. Claude Code settings will not be persisted."
  exit 0
fi

# Fallback for when the entrypoint could not fix ownership (e.g. the container does not run as root).
if [ ! -w "$MOUNT_POINT" ] && command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  sudo -n chown "$(id -u):$(id -g)" "$MOUNT_POINT" && sudo -n chmod 700 "$MOUNT_POINT"
fi

if [ ! -w "$MOUNT_POINT" ]; then
  err "$MOUNT_POINT is not writable by $(id -un 2>/dev/null || id -u). Claude Code settings will not be persisted."
  exit 1
fi

exit 0
