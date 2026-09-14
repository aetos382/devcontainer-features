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

if [ -z "${_REMOTE_USER:-}" ]; then
  echo "$FEATURE_ID: _REMOTE_USER is not set; install.sh must be run by the devcontainer CLI." >&2
  exit 1
fi
TARGET_USER="$_REMOTE_USER"
mkdir -p "$MOUNT_POINT"

# Docker initializes an empty named volume with the ownership of the image-side directory.
# This is intentionally redundant with entrypoint.sh, which re-fixes ownership on every container
# start and is what test/claude-code-persistence actually exercises for non-root correctness; if this
# chown alone were broken, entrypoint.sh (and post-create.sh's sudo fallback, when available) would
# silently cover for it. Not worth a dedicated test scenario for that failure mode.
if id -u "$TARGET_USER" >/dev/null 2>&1; then
  TARGET_GROUP="$(id -gn "$TARGET_USER")"
  chown "$TARGET_USER:$TARGET_GROUP" "$MOUNT_POINT"
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
