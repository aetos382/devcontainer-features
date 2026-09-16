#!/usr/bin/env bash
# devcontainer CLI と shellcheck の導入。devcontainer CLI はフィーチャーのテスト
# （devcontainer features test）に、shellcheck は install.sh 等の静的解析に使う。
# postCreateCommand ではなく updateContentCommand で入れるのは、Codespaces の
# prebuild にこの結果を含めるため。
set -euo pipefail

npm install -g @devcontainers/cli
bash "$(dirname "$0")/install-shellcheck.sh"
