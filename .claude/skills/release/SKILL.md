---
name: release
description: このリポジトリの devcontainer feature をリリースする。変更のある feature を洗い出し、バージョンを上げる PR を作ってマージし、release ワークフローを実行して ghcr.io への公開を確認する。
disable-model-invocation: true
---

# devcontainer feature のリリース

引数で feature ID が指定された場合はその feature だけを対象にする。指定がなければ `src/*` 配下のすべての feature を対象にする。

各ステップで想定外の結果になった場合は、先へ進まずにユーザーに報告する。

## 1. 前提条件の確認

以下を並行して確認し、1 つでも満たさなければ中断する。

- `git status --porcelain` が空であること。
- 現在のブランチが `main` で、`git fetch origin` 後に `origin/main` と一致していること。
- `gh auth status` のトークン スコープに `workflow` と `write:packages` または `repo` が含まれること。
- `devcontainer --version` が成功すること。

## 2. リリース対象の洗い出し

feature ごとに以下を取得する（feature 間は並行してよい）。

- ローカル バージョン: `jq -r .version src/<id>/devcontainer-feature.json`
- 公開済みバージョン: `devcontainer features info tags ghcr.io/aetos382/devcontainer-features/<id> --output-format json` の `publishedTags` のうち、`X.Y.Z` 形式の最大値。
  - `{}` が返り exit 1 になる場合は、未公開か非公開パッケージのどちらか。`gh api users/aetos382/packages/container/devcontainer-features%2F<id> --jq .visibility` で区別する（404 なら未公開）。
- 前回のバージョン変更コミット: `git log -1 --format=%H -G'"version"' -- src/<id>/devcontainer-feature.json`
- それ以降の変更: `git log --oneline <そのコミット>..HEAD -- src/<id>` と `git diff <そのコミット>..HEAD -- src/<id>`

以下のように分類し、表にしてユーザーに示す。

| 状態 | 条件 | 対応 |
|---|---|---|
| 初回リリース | 未公開 | 現在のバージョンのまま公開する |
| 公開待ち | ローカル > 公開済み | バージョン変更なしで公開する |
| 要バージョン アップ | ローカル = 公開済み、かつ前回のバージョン変更以降に `src/<id>` の変更がある | 3 へ |
| 対象外 | 上記以外 | 何もしない |

`README.md` はリリース時に自動生成されるため、`src/<id>/README.md` だけの変更は対象外として扱う。

## 3. バージョン アップ

変更内容から次の基準で上げる桁を提案し、**ユーザーの確認を得てから**進める。

- メジャー: 既存利用者の永続データが引き継がれなくなる、または挙動が非互換になる変更。volume 名の変更、マウント先の変更、`CLAUDE_CONFIG_DIR` の決定方法の変更、option の削除・意味の変更、`installsAfter` 等による前提条件の追加。
- マイナー: 後方互換な機能追加。option の追加、警告・検出の追加、対応環境の拡大。
- パッチ: バグ修正、ドキュメントのみの修正。

確認が取れたら以下を行う。

1. `release/<id>-v<新バージョン>` ブランチを作成する（複数 feature を同時に上げる場合は `release/<日付>`）。
2. `src/<id>/devcontainer-feature.json` の `version` を書き換える。
3. `<id>: v<新バージョン>` をメッセージとしてコミットし、push して PR を作成する。PR 本文には前回リリース以降の変更一覧と、上げた桁の根拠を書く。
4. `gh pr checks <PR> --watch` で CI の完了を待つ。失敗したら中断して報告する。
5. **ユーザーの確認を得てから** `gh pr merge <PR> --squash --delete-branch` でマージし、ローカルの `main` を `git pull --ff-only` で更新する。

## 4. 公開

公開対象が 1 つ以上ある場合のみ実行する。release ワークフローは `src/` 配下のすべての feature を一括で公開し、公開済みバージョンはスキップされる。

1. **ユーザーの確認を得てから** `gh workflow run release.yaml --ref main` を実行する。
2. `gh run list --workflow release.yaml --limit 1 --json databaseId,status` で実行 ID を取得し、`gh run watch <ID> --exit-status` で完了を待つ。失敗したら `gh run view <ID> --log-failed` の内容を報告する。

## 5. 公開後の確認

1. 公開した各 feature について `devcontainer features info tags` を再実行し、新バージョンと、メジャー・マイナーのタグ（例: `1`, `1.1`）が含まれることを確認する。
2. 初回リリースの場合、ghcr のパッケージは既定で非公開になる。`gh api users/aetos382/packages/container/devcontainer-features%2F<id> --jq .visibility` が `public` でなければ、`https://github.com/users/aetos382/packages/container/devcontainer-features%2F<id>/settings` で公開に変更するようユーザーに依頼する（API では変更できない）。
3. ワークフローがドキュメント更新 PR（`automated-documentation-update-*`）を作成していれば、その URL を報告する。

最後に、公開したバージョン、PR、ワークフロー実行の URL をまとめて報告する。
