#!/bin/bash
# Ensures that the feature installs its own download dependencies (curl, ca-certificates) on the
# older supported Debian release, which lacks them. The CI base-image matrix already covers this,
# but a scenario keeps Debian 12 covered even if the matrix is narrowed. Everything test.sh asserts
# holds here too, so it is reused rather than duplicated.
set -e

exec bash "$(dirname "$0")/test.sh"
