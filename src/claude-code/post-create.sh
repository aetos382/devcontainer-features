#!/bin/sh
# Untested branches (see test/claude-code): "mount point is not a mount" (MOUNT_POINT is hardcoded,
# so simulating it needs an actual unmount), "still not writable after the sudo fallback" (needs a
# container without passwordless sudo, or a temporary sudoers edit), and "existing ~/.claude blocks
# an empty volume" (needs a base image or feature that seeds ~/.claude before this runs). All were
# judged too heavy for the coverage gained; revisit if a lighter way to simulate them turns up.
set -u

FEATURE_ID='claude-code'
MOUNT_POINT='/var/lib/claude-code'
SHARE_DIR="/usr/local/share/${FEATURE_ID}"

# devcontainer-feature.json cannot make postCreateCommand conditional on an option, so the marker
# install.sh writes is what distinguishes "persistence is on" from "the volume is mounted but unused".
# Without this, every container built with persistence off would warn about CLAUDE_CONFIG_DIR.
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

if [ -z "$(find "$MOUNT_POINT" -mindepth 1 -print -quit 2>/dev/null)" ] \
   && { [ -e "$HOME/.claude" ] || [ -e "$HOME/.claude.json" ]; }; then
  err "$MOUNT_POINT is empty, but '$HOME/.claude' or '$HOME/.claude.json' already has content. This likely means another feature or command populated it before this feature's postCreateCommand ran; check your feature install order (installsAfter / overrideFeatureInstallOrder)."
  exit 1
fi

# Fallback for when the entrypoint could not fix ownership (e.g. the container does not run as root).
if [ ! -w "$MOUNT_POINT" ] && command -v 'sudo' >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  sudo -n chown "$(id -u):$(id -g)" "$MOUNT_POINT" && sudo -n chmod 700 "$MOUNT_POINT"
fi

if [ ! -w "$MOUNT_POINT" ]; then
  err "$MOUNT_POINT is not writable by $(id -un 2>/dev/null || id -u). Claude Code settings will not be persisted."
  exit 1
fi

exit 0
