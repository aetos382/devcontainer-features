#!/bin/sh

FEATURE_ID='claude-code'
MOUNT_POINT='/var/lib/claude-code'
SHARE_DIR="/usr/local/share/${FEATURE_ID}"

# devcontainer-feature.json cannot make the entrypoint conditional on an option, so the marker
# install.sh writes is what distinguishes "persistence is on" from "the volume is mounted but unused".
[ -e "$SHARE_DIR/persistence-enabled" ] || exit 0
[ "$(id -u)" -eq 0 ] || exit 0
[ -d "$MOUNT_POINT" ] || exit 0

TARGET_USER="$(cat "${SHARE_DIR}/remote-user")" || exit 0
uid="$(id -u "$TARGET_USER" 2>/dev/null)" || exit 0
gid="$(id -g "$TARGET_USER")" || exit 0

# Re-evaluated on every start because updateRemoteUserUID changes the UID after the build without touching this directory.
if [ "$(stat -c %u "$MOUNT_POINT")" != "$uid" ] || [ -n "$(find "$MOUNT_POINT" ! -user "$uid" | head -n 1)" ]; then
  echo "$FEATURE_ID: changing ownership of $MOUNT_POINT to $TARGET_USER ($uid:$gid)." >&2
  # -h: the volume is user-writable, so symlinks must not be followed as root.
  chown -R -h "$uid:$gid" "$MOUNT_POINT"
fi
chmod 700 "$MOUNT_POINT"
