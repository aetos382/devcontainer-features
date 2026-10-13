# CLAUDE.md

## シェルスクリプト

- 特別な理由がない限り、すべての文字列は引用符で囲む。
- string interpolation が必要な場合は `"foo${VAR}bar"` のように二重引用符を使う。
- string interpolation が不要な場合は `'foobar'` のように単一引用符を使う。
- このルールに従えない場合、その理由をコメントで付記する。

## gh-actions-lock のバージョン

`.github/workflows/actions.lock` を作る gh の拡張機能 gh-actions-lock のバージョンは `.devcontainer/versions.sh` の `GH_ACTIONS_LOCK_VERSION` と `renovate.json` の `constraints.ghActionsLock` の 2 箇所にあり、同じ値にする。Renovate は共有 preset の `default` で両方を更新する。手で変えるときも両方を変える。後者は Renovate がロックファイルを作り直すときに使うバージョンである。
