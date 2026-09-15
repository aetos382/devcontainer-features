#!/usr/bin/env bash
# main への直接コミットを止める。main の更新は PR 経由のみとするため。
# commit の作成時に呼ばれる仕組みであり、git rebase や git reset のように
# commit の作成を経由せずに main の ref を書き換える操作までは防げない。
set -euo pipefail

branch="$(git branch --show-current)"
if [ "$branch" = "main" ]; then
  echo "Direct commits to main are not allowed. Please create a branch." >&2
  exit 1
fi
