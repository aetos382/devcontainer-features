#!/bin/sh

FEATURE_ID='claude-code'
MOUNT_POINT='/var/lib/claude-code'
SHARE_DIR="/usr/local/share/${FEATURE_ID}"

[ -e "$SHARE_DIR/persistence-enabled" ] || exit 0
[ "$(id -u)" -eq 0 ] || exit 0
[ -d "$MOUNT_POINT" ] || exit 0

TARGET_USER="$(cat "${SHARE_DIR}/remote-user")" || {
  echo "$FEATURE_ID: warning: cannot read ${SHARE_DIR}/remote-user; skipping the ownership fix for $MOUNT_POINT." >&2
  exit 0
}
uid="$(id -u "$TARGET_USER" 2>/dev/null)" || {
  echo "$FEATURE_ID: warning: user '$TARGET_USER' does not exist; skipping the ownership fix for $MOUNT_POINT." >&2
  exit 0
}
gid="$(id -g "$TARGET_USER")" || exit 0

# Re-evaluated on every start because updateRemoteUserUID changes the UID after the build without touching this directory.
if [ "$(stat -c '%u' "$MOUNT_POINT")" != "$uid" ] || [ -n "$(find "$MOUNT_POINT" '!' -user "$uid" | head -n 1)" ]; then
  echo "$FEATURE_ID: changing ownership of $MOUNT_POINT to $TARGET_USER ($uid:$gid)." >&2
  # -h: the volume is user-writable, so symlinks must not be followed as root.
  # A failure is reported but does not stop the container; post-create.sh retries and fails loudly.
  if ! chown -R -h "$uid:$gid" "$MOUNT_POINT"; then
    echo "$FEATURE_ID: warning: failed to change ownership of $MOUNT_POINT; postCreateCommand will retry with sudo if available." >&2
  fi
fi
chmod 700 "$MOUNT_POINT"
