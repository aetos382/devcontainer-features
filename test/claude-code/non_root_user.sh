#!/bin/bash
# Ensures that a non-root remote user can run the CLI and owns the volume, that the entrypoint and
# post-create.sh restore ownership and mode when they drift, and that post-create.sh fails when the
# volume cannot be made usable or another tool seeded ~/.claude first.
#
# A command string passed to 'bash -c' is single-quoted whenever it holds no value of this script's
# own, so that its '$' reaches that nested shell unexpanded; SC2016 flags exactly that and is not a
# finding here. The checks that pass MOUNT_POINT in use double quotes instead.
# shellcheck disable=SC2016
set -e

# dev-container-features-test-lib is provided by the devcontainer CLI inside the test container, so
# ShellCheck has nothing to follow here. Suppressed per call site rather than for the whole
# directory, to keep a mistyped path to a script that does live in the repository detectable.
# shellcheck source=/dev/null
source 'dev-container-features-test-lib'

MOUNT_POINT='/var/lib/claude-code'
POST_CREATE='/usr/local/share/claude-code/post-create.sh'

check 'running as vscode' bash -c '[ "$(id -un)" = "vscode" ]'

# Must run before anything writes to the volume: the branch under test requires it to be empty.
check 'post-create fails when ~/.claude exists but the volume is empty' bash -c "
  [ -z \"\$(find '$MOUNT_POINT' -mindepth 1 -print -quit)\" ] || exit 1
  h=\$(mktemp -d)
  mkdir \"\$h/.claude\"
  out=\$(HOME=\"\$h\" CLAUDE_CONFIG_DIR='$MOUNT_POINT' '$POST_CREATE' 2>&1)
  [ \$? -eq 1 ] && echo \"\$out\" | grep -q 'is empty'
"

# HOME is redirected so that the run cannot seed ~/.claude, which would make the post-create runs
# below fail on their empty-volume check.
check 'non-root user can run claude' bash -c 'HOME="$(mktemp -d)" claude --version'

check 'mount point is owned by vscode' bash -c "[ \"\$(stat -c '%U' '$MOUNT_POINT')\" = 'vscode' ]"
check 'mount point is writable' bash -c "touch '$MOUNT_POINT/.write-test' && rm '$MOUNT_POINT/.write-test'"
check 'CLAUDE_CONFIG_DIR defaults to mount point' bash -c "[ \"\$(bash -lc 'printenv CLAUDE_CONFIG_DIR')\" = '$MOUNT_POINT' ]"

# Simulates ownership left stale by a UID change (updateRemoteUserUID) and ensures the entrypoint restores it recursively.
sudo chown -R 'root:root' "$MOUNT_POINT"
sudo chmod 755 "$MOUNT_POINT"
sudo touch "$MOUNT_POINT/.stale"
sudo '/usr/local/share/claude-code/entrypoint.sh'
check 'entrypoint restores mount point ownership' bash -c "[ \"\$(stat -c '%U' '$MOUNT_POINT')\" = 'vscode' ]"
check 'entrypoint restores ownership of volume contents' bash -c "[ \"\$(stat -c '%U' '$MOUNT_POINT/.stale')\" = 'vscode' ]"
check 'entrypoint restores mode 700' bash -c "[ \"\$(stat -c '%a' '$MOUNT_POINT')\" = '700' ]"
rm -f "$MOUNT_POINT/.stale"

# Simulates ownership stuck as root (e.g. the entrypoint did not run as root) and ensures post-create.sh's sudo fallback restores writability.
sudo chown 'root:root' "$MOUNT_POINT"
sudo chmod 755 "$MOUNT_POINT"
CLAUDE_CONFIG_DIR="$MOUNT_POINT" "$POST_CREATE"
check 'post-create sudo fallback restores ownership' bash -c "[ \"\$(stat -c '%U' '$MOUNT_POINT')\" = 'vscode' ]"
check 'post-create sudo fallback restores mode 700' bash -c "[ \"\$(stat -c '%a' '$MOUNT_POINT')\" = '700' ]"

# Simulates a file left with a stale owner while the directory itself is fine, which a check on the
# directory alone would miss.
sudo touch "$MOUNT_POINT/.stale-content"
check 'post-create sudo fallback restores ownership of volume contents' bash -c "
  CLAUDE_CONFIG_DIR='$MOUNT_POINT' '$POST_CREATE' &&
    [ \"\$(stat -c '%U' '$MOUNT_POINT/.stale-content')\" = 'vscode' ]
"
rm -f "$MOUNT_POINT/.stale-content"

# A sudo that always fails stands in for a container without passwordless sudo.
fake_sudo_dir="$(mktemp -d)"
printf '#!/bin/sh\nexit 1\n' > "$fake_sudo_dir/sudo"
chmod +x "$fake_sudo_dir/sudo"
sudo chown 'root:root' "$MOUNT_POINT"
check 'post-create fails when sudo cannot fix ownership' bash -c "
  out=\$(PATH='$fake_sudo_dir':\"\$PATH\" HOME=\$(mktemp -d) CLAUDE_CONFIG_DIR='$MOUNT_POINT' '$POST_CREATE' 2>&1)
  [ \$? -eq 1 ] && echo \"\$out\" | grep -q 'not owned by and accessible to'
"
sudo chown 'vscode:vscode' "$MOUNT_POINT"

reportResults
