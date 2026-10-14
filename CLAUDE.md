# CLAUDE.md

## gh-actions-lock のバージョン

`.github/workflows/actions.lock` を作る gh の拡張機能 gh-actions-lock のバージョンは `.devcontainer/versions.sh` の `GH_ACTIONS_LOCK_VERSION` と `renovate.json` の `constraints.ghActionsLock` の 2 箇所にあり、同じ値にする。Renovate は共有 preset の `default` で両方を更新する。手で変えるときも両方を変える。後者は Renovate がロックファイルを作り直すときに使うバージョンである。
