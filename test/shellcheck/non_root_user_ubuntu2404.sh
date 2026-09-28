#!/bin/bash
# Ensures that a non-root remote user can run shellcheck on the older supported Ubuntu LTS as well.
# The assertions are the same as in non_root_user.sh, which runs on the newer one.
set -e

exec bash "$(dirname "$0")/non_root_user.sh"
