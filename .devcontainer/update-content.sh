#!/usr/bin/env bash
# 開発ツールの導入。
# - devcontainer CLI: フィーチャーのテスト（devcontainer features test）に使う。
# - gh-actions-lock: actions.lock の更新と、pre-commit hook での検証に使う。
# postCreateCommand ではなく updateContentCommand で入れるのは、Codespaces の
# prebuild にこの結果を含めるため。
set -euo pipefail

# shellcheck source=SCRIPTDIR/versions.sh
source "$(dirname "$0")/versions.sh"

npm install -g '@devcontainers/cli'

# github-cli feature の extensions オプションではバージョンを固定できないので、ここで入れる。
# 別のバージョンが入っているときは、外してから入れ直す。導入済みの拡張機能に対して install は
# --pin を見ないため。--force を付けると最新版に上げて固定も外し、付けないと何もしない
# （gh 2.102.0 で確認）。
installed="$(gh extension list | awk -F'\t' '$2 == "github/gh-actions-lock" { print $3 }')"
if [ "${installed}" != "${GH_ACTIONS_LOCK_VERSION}" ]; then
  if [ -n "${installed}" ]; then
    gh extension remove 'actions-lock'
  fi
  gh extension install 'github/gh-actions-lock' --pin "${GH_ACTIONS_LOCK_VERSION}"
fi
# pre-commit hook がこの拡張機能を使うので、動かないことにコミットの時点ではなく作成の時点で
# 気付けるよう、起動できることも確かめる。
if ! gh actions-lock --help >/dev/null 2>&1; then
  echo "update-content: gh actions-lock does not run after installing gh-actions-lock ${GH_ACTIONS_LOCK_VERSION}." >&2
  exit 1
fi
