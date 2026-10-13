# shellcheck shell=bash
# 開発ツールのバージョン。source して使う。
# 読むのは update-content.sh（devcontainer への導入）、CI の actions-lock ジョブ、
# pre-commit hook（ツールが無いときの案内に使う）。
#
# export は代入とは別の行に書く。Renovate の custom manager（presets/devcontainer）は、
# `# renovate:` コメントの直後の行が `XXX_VERSION='...'` で始まることを前提にしているため。
# export しておくと、source 先で使う変数として ShellCheck の SC2034 も出なくなる。

# gh の拡張機能 gh-actions-lock。renovate.json の constraints.ghActionsLock と同じ値にする。
# Renovate が actions.lock を作り直すときのバージョンを、手元や CI と揃えるため。
# renovate: datasource=github-releases depName=github/gh-actions-lock
GH_ACTIONS_LOCK_VERSION='v0.1.6'
export GH_ACTIONS_LOCK_VERSION
