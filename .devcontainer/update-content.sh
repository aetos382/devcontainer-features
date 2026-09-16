#!/usr/bin/env bash
# devcontainer CLI の導入。フィーチャーのテスト（devcontainer features test）に使う。
# postCreateCommand ではなく updateContentCommand で入れるのは、Codespaces の
# prebuild にこの結果を含めるため。
set -euo pipefail

npm install -g @devcontainers/cli
