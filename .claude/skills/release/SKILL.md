---
name: release
description: このリポジトリの devcontainer feature をリリースする。変更のある feature を洗い出し、バージョンを上げる PR を作ってマージし、release ワークフローを実行して ghcr.io への公開を確認する。
disable-model-invocation: true
---

# devcontainer feature のリリース

引数で feature ID が指定された場合はその feature だけを対象にする。指定がなければ `src/*` 配下のすべての feature を対象にする。

各ステップで想定外の結果になった場合は、先へ進まずにユーザーに報告する。PR のマージと公開の実行は、いずれもユーザーの確認を得てから行う。

## 1. 前提条件の確認

- `command -v git gh curl jq` がすべて解決すること。この 4 つ以外の外部コマンドは使わない。`jq` は Windows に標準では入っていないため、欠けていたらユーザーに報告して中断する。
- `git status --porcelain` が空であること。
- 現在のブランチが `main` で、`git fetch origin` の後に `origin/main` と一致していること。fetch を省略してリモート追跡参照を見ると、マージ済みの内容を未マージと誤認する。

公開そのものは release ワークフロー上の `devcontainers/action` が行い、公開後の確認は curl と jq で足りるため、ローカルに devcontainer CLI と Node.js は不要。

## 2. リリース対象の洗い出し

feature ごとに以下を取得する（feature 間は並行してよい）。

- ローカル バージョン: `jq -r .version src/<id>/devcontainer-feature.json`
- 公開済みかどうか: `gh api users/aetos382/packages/container/devcontainer-features%2F<id> --jq .visibility`
  - 404（Package not found）なら未公開。
  - 値が返るか、`read:packages` スコープ不足の 403 が返るならパッケージは存在する（= 公開済み）。存在確認はスコープ検査より先に行われるため、403 と 404 で区別できる。
- 前回のバージョン変更コミット: `git log -1 --format=%H -G'"version"' -- src/<id>/devcontainer-feature.json`
- それ以降の変更: `git log --oneline <そのコミット>..HEAD -- src/<id>` と `git diff <そのコミット>..HEAD -- src/<id>`

以下のように分類し、表にしてユーザーに示す。

| 状態 | 条件 | 対応 |
|---|---|---|
| 初回リリース | 未公開 | 現在のバージョンのまま公開する |
| 要バージョン アップ | 公開済みで、前回のバージョン変更以降に `src/<id>` の変更がある | 3 へ |
| 対象外 | 公開済みで、変更がない | 何もしない |

`src/<id>/README.md` はリリース時に自動生成されるため、その変更だけの場合は変更なしとして扱う。

## 3. バージョン アップ

変更内容から次の基準で上げる桁を提案し、**ユーザーの確認を得てから**進める。

- メジャー: 既存利用者の永続データが引き継がれなくなる、または挙動が非互換になる変更。volume 名の変更、マウント先の変更、`CLAUDE_CONFIG_DIR` の決定方法の変更、option の削除・意味の変更、`dependsOn` 等による前提条件の追加。
- マイナー: 後方互換な機能追加。option の追加、警告・検出の追加、対応環境の拡大。
- パッチ: バグ修正、ドキュメントのみの修正。

確認が取れたら以下を行う。

1. `release/<id>-v<新バージョン>` ブランチを作成する（複数 feature を同時に上げる場合は `release/<日付>`）。
2. `src/<id>/devcontainer-feature.json` の `version` を書き換える。
3. `<id>: v<新バージョン>` をメッセージとしてコミットし、push して PR を作成する。PR 本文には前回リリース以降の変更一覧と、上げた桁の根拠を書く。
4. `gh pr checks <PR> --watch` で CI の完了を待つ。
5. マージの確認を得たら `gh pr merge <PR> --merge --delete-branch` を実行し、ローカルの `main` を `git pull --ff-only` で更新する。

## 4. 公開

公開対象が 1 つ以上ある場合のみ実行する。release ワークフローは `src/` 配下のすべての feature を一括で公開し、公開済みバージョンはスキップされる。

1. `gh run list --workflow release.yaml --limit 1 --json databaseId --jq '.[0].databaseId // empty'` で dispatch 前の最新 run ID を控える。
2. 確認を得たら `gh workflow run release.yaml --ref main` を実行する。
3. `gh workflow run` は run を非同期にキューへ投入するだけで ID を返さないため、手順 1 と同じコマンドを数秒間隔で叩き、控えた ID と異なる ID が現れるのを待つ。それが今回の run。`gh run watch <ID> --exit-status` で完了を待ち、失敗したら `gh run view <ID> --log-failed` の内容を報告する。

## 5. 公開後の確認

1. 公開した各 feature のタグを、ghcr の匿名 API で確認する。public なパッケージは認証なしで参照できるため、devcontainer CLI も `read:packages` スコープも要らない。

   ```bash
   repo=aetos382/devcontainer-features/<id>
   token=$(curl -sf "https://ghcr.io/token?service=ghcr.io&scope=repository:${repo}:pull" | jq -r .token)
   curl -sf -H "Authorization: Bearer ${token}" "https://ghcr.io/v2/${repo}/tags/list" | jq -r '.tags[]'
   ```

   - 新バージョンと、メジャー・マイナーの動くタグ（`1.0.0` なら `1` と `1.0`）、`latest` が揃っていることを確認する。
   - token エンドポイントが 403 `DENIED` を返す場合はパッケージが非公開。初回リリースでは ghcr のパッケージが既定で**非公開**になるため、`https://github.com/users/aetos382/packages/container/devcontainer-features%2F<id>/settings` で public に変更するようユーザーに依頼する（API では変更できない）。変更後に上のコマンドを再実行して確認する。
2. ワークフローがドキュメント更新 PR（`automated-documentation-update-*`）を作成していれば、以下を行う。
   1. `gh pr close <PR>` の後に `gh pr reopen <PR>` を実行して CI を起動する。この PR は `GITHUB_TOKEN` で作成されるため `pull_request` のワークフローが走らず、main branch の ruleset が要求する CI のチェックが報告されないままになる。人の操作による reopen で初めてワークフローが動く。
   2. `gh pr checks <PR> --watch` で CI の完了を待つ。
   3. マージの確認を得たら `gh pr merge <PR> --merge --delete-branch` を実行し、ローカルの `main` を `git pull --ff-only` で更新する。
最後に、公開したバージョン、PR、ワークフロー実行の URL をまとめて報告する。
