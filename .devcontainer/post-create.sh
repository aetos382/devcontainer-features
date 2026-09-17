#!/usr/bin/env bash
# devcontainer / Codespaces の初期化。
set -euo pipefail

cd "$(dirname "$0")/.."

# main への直接コミットを止める pre-commit hook（Config-based hooks）の定義を
# .gitconfig から取り込む。取り込まないと hook が有効にならない。
# 何度実行しても値が重複しないよう、既に入っているかを確認する。
# grep へのパイプで確認すると、grep -q が先に終了して git config が SIGPIPE で落ち、
# pipefail のせいで「未設定」と誤判定されて重複追加されることがある。git config get 自身の
# 値フィルターで確認する。
if ! git config get --local --all --fixed-value --value='../.gitconfig' 'include.path' >/dev/null 2>&1; then
  git config set --append --local 'include.path' '../.gitconfig'
fi

# .claude/settings.json に書かれている marketplace / plugin をプロジェクト スコープで
# インストールする。settings.json をマスターとし、ここではコマンドラインを展開しない。
settings_file='.claude/settings.json'

# プロセス置換の中で jq が失敗しても set -e では検知できないため、先に変数へ受ける。
# github 以外の source は扱えないので、黙って飛ばさずにエラーにする。
repos=$(jq -r '
  .extraKnownMarketplaces // {} | to_entries[]
  | if .value.source.source == "github" then .value.source.repo
    else error("unsupported marketplace source: \(.key) (\(.value.source.source))")
    end
' "${settings_file}")

plugins=$(jq -r '.enabledPlugins // {} | to_entries[] | select(.value == true) | .key' "${settings_file}")

# claude が標準入力を読むと、ループに渡している残りの行が消費されてしまうため、
# claude の標準入力は /dev/null につなぐ。
while IFS= read -r repo; do
  [[ -n "${repo}" ]] || continue
  claude plugin marketplace add --scope project "${repo}" < /dev/null
done <<< "${repos}"

while IFS= read -r plugin; do
  [[ -n "${plugin}" ]] || continue
  claude plugin install --scope project --yes "${plugin}" < /dev/null
done <<< "${plugins}"
