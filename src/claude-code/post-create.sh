#!/bin/sh
# Untested branch (see test/claude-code): "mount point is not a mount", because MOUNT_POINT is
# hardcoded and simulating it needs an actual unmount.
set -u

FEATURE_ID='claude-code'
MOUNT_POINT='/var/lib/claude-code'
SHARE_DIR="/usr/local/share/${FEATURE_ID}"

[ -e "$SHARE_DIR/persistence-enabled" ] || exit 0

warn() {
  echo "$FEATURE_ID: warning: $*" >&2
}

err() {
  echo "$FEATURE_ID: error: $*" >&2
}

if [ -z "${CLAUDE_CONFIG_DIR:-}" ]; then
  # Double-quoted despite having nothing to interpolate: the message contains an apostrophe, which
  # a single-quoted string cannot hold.
  warn "CLAUDE_CONFIG_DIR is not set. /etc/profile.d may not have been loaded (e.g. \"userEnvProbe\": \"none\", or the remote user's login shell is zsh, which does not read /etc/profile.d by default). Claude Code settings will not be persisted."
  exit 0
fi

if [ "${CLAUDE_CONFIG_DIR%/}" != "$MOUNT_POINT" ]; then
  warn "CLAUDE_CONFIG_DIR is set to '$CLAUDE_CONFIG_DIR', not '$MOUNT_POINT'. Claude Code settings will not be persisted by this feature."
  exit 0
fi

if ! grep -q " $MOUNT_POINT " '/proc/mounts'; then
  warn "$MOUNT_POINT is not a mount point. Claude Code settings will not be persisted."
  exit 0
fi

# Contents are checked too: after a UID change, files such as .credentials.json can keep the old
# owner while the directory itself looks fine, and Claude Code then asks to log in again for no
# visible reason. An unreadable directory also has to count, or find would report it as empty.
needs_ownership_fix() {
  [ ! -r "$MOUNT_POINT" ] || [ ! -w "$MOUNT_POINT" ] || [ ! -x "$MOUNT_POINT" ] ||
    [ -n "$(find "$MOUNT_POINT" '!' -user "$(id -u)" -print -quit 2>/dev/null)" ]
}

# Fallback for when the entrypoint could not fix ownership (e.g. the container does not run as root).
if needs_ownership_fix && command -v 'sudo' >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  sudo -n chown -R -h "$(id -u):$(id -g)" "$MOUNT_POINT" && sudo -n chmod 700 "$MOUNT_POINT"
fi

if needs_ownership_fix; then
  err "$MOUNT_POINT or its contents are not owned by and accessible to $(id -un 2>/dev/null || id -u). Claude Code settings will not be persisted."
  exit 1
fi

if [ -z "$(find "$MOUNT_POINT" -mindepth 1 -print -quit)" ] \
   && { [ -e "$HOME/.claude" ] || [ -e "$HOME/.claude.json" ]; }; then
  err "$MOUNT_POINT is empty, but '$HOME/.claude' or '$HOME/.claude.json' already exists. This likely means another feature or command populated it before this feature's postCreateCommand ran; check your feature install order (installsAfter / overrideFeatureInstallOrder)."
  exit 1
fi

exit 0
