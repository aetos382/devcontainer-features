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
# インストールする。ローカル（Windows を含む）でも同じ処理を使うので、本体は PowerShell で書いてある。
pwsh -NoProfile -File .claude/install-plugins.ps1
