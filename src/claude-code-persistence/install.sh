#!/bin/sh
set -eu

FEATURE_ID=claude-code-persistence
MOUNT_POINT=/var/lib/claude-code-persistence
SHARE_DIR=/usr/local/share/$FEATURE_ID

if [ "$(id -u)" -ne 0 ]; then
  echo "$FEATURE_ID: install.sh must be run as root." >&2
  exit 1
fi

cd "$(dirname "$0")"

# Docker initializes an empty named volume with the ownership of the image-side directory.
TARGET_USER="${_REMOTE_USER:-root}"
mkdir -p "$MOUNT_POINT"
if id -u "$TARGET_USER" >/dev/null 2>&1; then
  chown "$TARGET_USER:$(id -gn "$TARGET_USER")" "$MOUNT_POINT"
  chmod 700 "$MOUNT_POINT"
else
  echo "$FEATURE_ID: warning: user '$TARGET_USER' does not exist at build time; $MOUNT_POINT is left owned by root." >&2
fi

# The guard must live inside the snippet so that values from containerEnv, applied after the build, win.
cat > /etc/profile.d/$FEATURE_ID.sh <<'EOF'
if [ -z "${CLAUDE_CONFIG_DIR:-}" ]; then
  export CLAUDE_CONFIG_DIR=/var/lib/claude-code-persistence
fi
EOF
chmod 644 /etc/profile.d/$FEATURE_ID.sh

mkdir -p "$SHARE_DIR"
cp post-create.sh entrypoint.sh "$SHARE_DIR/"
chmod 755 "$SHARE_DIR/post-create.sh" "$SHARE_DIR/entrypoint.sh"
printf '%s\n' "$TARGET_USER" > "$SHARE_DIR/remote-user"
