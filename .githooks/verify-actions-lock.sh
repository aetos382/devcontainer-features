#!/usr/bin/env bash
# .github/workflows 配下がコミットに含まれるとき、ワークフローの uses が actions.lock のエントリと
# 対応していることを gh actions-lock で確かめる。
# ロックファイルとのずれや、読めないロックファイルは、ワークフローを見ただけでは分からないので、
# コミットの時点で止める。
set -euo pipefail

# git diff の出力は、いったん変数に受けて終了コードを確かめる。プロセス置換で読むと終了コードが
# 捨てられ、パイプを if の条件にすると git diff の失敗と一致なしを区別できない。どちらも、
# 対象なしとして検証を飛ばしてしまう。
# 削除も対象にする。ロックファイルを消したコミットも検証したいため。
if ! staged="$(git diff --cached --name-only -- '.github/workflows')"; then
  echo 'verify-actions-lock: failed to list staged files.' >&2
  exit 1
fi
if [ -z "${staged}" ]; then
  exit 0
fi

# ワークフローが 1 つも残らないコミットは検証しない。固定する対象が無いうえ、gh actions-lock は
# ワークフローが無いこと自体をエラーにするので（v0.1.6 で確認）、最後のワークフローを消すコミットが
# 通せなくなる。
# :(glob) を付けて、* がサブディレクトリまで一致しないようにする。
if ! workflows="$(git ls-files -- ':(glob).github/workflows/*.yml' ':(glob).github/workflows/*.yaml')"; then
  echo 'verify-actions-lock: failed to list staged workflows.' >&2
  exit 1
fi
if [ -z "${workflows}" ]; then
  exit 0
fi

# 導入せずにその場で実行する手段が無いので、無ければ失敗させる。
if ! command -v gh >/dev/null 2>&1 || ! gh actions-lock --help >/dev/null 2>&1; then
  # hook はリポジトリのルートで実行される。
  # shellcheck source=SCRIPTDIR/../.devcontainer/versions.sh
  source '.devcontainer/versions.sh'
  echo 'verify-actions-lock: the gh actions-lock extension is not available. Install it with:' >&2
  echo "  gh extension install github/gh-actions-lock --pin ${GH_ACTIONS_LOCK_VERSION}" >&2
  exit 1
fi

# 作業ツリーではなくステージされた内容を検証する。
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
git ls-files -z -- '.github/workflows' | git checkout-index --prefix="${tmp_dir}/" -z --stdin

# --verify-local はオフラインで、各 uses がロックファイルのエントリと対応しているかを見る。
# エントリの無い uses、ref の食い違い、残っているワークフローの記録にあって uses の無いエントリは
# 失敗になる。消したワークフローの記録や、どこからも参照されない dependencies のエントリは
# 検出されない（v0.1.6 で確認）。
# コミット SHA の正しさは見ないので、CI の actions-lock ジョブ（--verify）で確かめる。
# --no-fix を付けないと、検査の前に同一リポジトリの `uses: ./…` を書き換える。
if ! (cd "${tmp_dir}" && gh actions-lock --no-fix --no-interactive --verify-local); then
  echo 'verify-actions-lock: run "gh actions-lock" and stage the result.' >&2
  exit 1
fi
