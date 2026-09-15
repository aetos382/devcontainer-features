---
name: release
description: このリポジトリの devcontainer feature をリリースする。変更のある feature を洗い出し、バージョンを上げる PR を作ってマージし、release ワークフローを実行して ghcr.io への公開を確認する。
disable-model-invocation: true
---

# devcontainer feature のリリース

引数で feature ID が指定された場合はその feature だけを対象にする。指定がなければ `src/*` 配下のすべての feature を対象にする。

各ステップで想定外の結果になった場合は、先へ進まずにユーザーに報告する。PR のマージと公開の実行は、いずれもユーザーの確認を得てから行う。

## 1. 前提条件の確認

- `command -v git gh curl jq` がすべて解決すること。`jq` は Windows に標準では入っていないため、欠けていたらユーザーに報告して中断する。この 4 つと POSIX の標準的なコマンド（`grep`、`sort`、`tail` など）以外は使わない。
- `git status --porcelain` が空であること。
- 現在のブランチが `main` で、`git fetch origin` の後に `origin/main` と一致していること。fetch を省略してリモート追跡参照を見ると、マージ済みの内容を未マージと誤認する。

公開そのものは release ワークフロー上の `devcontainers/action` が行い、公開後の確認は curl と jq で足りるため、ローカルに devcontainer CLI と Node.js は不要。

## 2. リリース対象の洗い出し

feature ごとに以下を取得する（feature 間は並行してよい）。

- ローカル バージョン: `jq -r .version src/<id>/devcontainer-feature.json`
- 公開済みバージョン: 後述の「公開済みタグの取得」で得たタグのうち、`X.Y.Z` 形式の最大値。
  - タグが取得できなかった場合、未公開か非公開のどちらか。`gh api users/aetos382/packages/container/devcontainer-features%2F<id> --jq .visibility` で区別する。404（Package not found）なら未公開。403（`read:packages` スコープ不足）または値が返るならパッケージは存在するので非公開。存在確認はスコープ検査より先に行われるため、403 と 404 で区別できる。
  - 非公開だった場合は公開済みバージョンが判定できないため、中断して可視性を public に変更するようユーザーに依頼する（手順 5.1 を参照）。
- 前回のバージョン変更コミット: `git log -1 --format=%H -G'"version"' -- src/<id>/devcontainer-feature.json`
- それ以降の変更: `git log --oneline <そのコミット>..HEAD -- src/<id>` と `git diff <そのコミット>..HEAD -- src/<id>`

以下のように分類し、表にしてユーザーに示す。

| 状態 | 条件 | 対応 |
|---|---|---|
| 初回リリース | 未公開 | 現在のバージョンのまま公開する |
| 公開待ち | ローカル > 公開済み | バージョン変更なしで公開する（4 へ） |
| 要バージョン アップ | ローカル = 公開済みで、前回のバージョン変更以降に `src/<id>` の変更がある | 3 へ |
| 異常 | ローカル < 公開済み | 中断してユーザーに報告する |
| 対象外 | 上記以外 | 何もしない |

`公開待ち` を落とさないこと。バージョン アップ PR をマージした後、release ワークフローの実行前や実行失敗後にこの手順を再実行すると、直前のバージョン変更コミット以降に `src/<id>` の変更が無いため、ローカル バージョンとの比較なしでは `対象外` と誤判定され、未公開のバージョンが永久に publish されなくなる。

`src/<id>/README.md` はリリース時に自動生成されるため、その変更だけの場合は変更なしとして扱う。

### 公開済みタグの取得

public なパッケージは認証なしで参照できるため、devcontainer CLI も `read:packages` スコープも要らない。手順 5.1 でも同じ手順を使う。

```bash
repo=aetos382/devcontainer-features/<id>
resp=$(curl -sS "https://ghcr.io/token?service=ghcr.io&scope=repository:${repo}:pull")
token=$(printf '%s' "$resp" | jq -r '.token // empty')
if [ -z "$token" ]; then
  printf 'タグ取得不可（非公開または未公開）: %s\n' "$resp"
else
  curl -sS -H "Authorization: Bearer ${token}" "https://ghcr.io/v2/${repo}/tags/list" | jq -r '.tags[]'
fi
```

`curl` に `-f` を付けたうえで `jq` へパイプしないこと。パイプの終了状態は末尾の `jq` で決まり、空入力の `jq -r` は成功するため、token が空でも失敗が検出できない。加えて `-f` はエラー本文を捨てるので、非公開を示す 403 `DENIED` が読めなくなる。上記のように応答をいったん受け取り、token が空かどうかで判定する。

`X.Y.Z` 形式の最大値は `grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1` で取れる。

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

1. 公開した各 feature について、手順 2 の「公開済みタグの取得」を再実行する。
   - 新バージョンと、メジャー・マイナーの動くタグ（`1.0.0` なら `1` と `1.0`）、`latest` が揃っていることを確認する。
   - タグが取得できず、応答が 403 `DENIED` の場合はパッケージが非公開。初回リリースでは ghcr のパッケージが既定で**非公開**になるため、`https://github.com/users/aetos382/packages/container/devcontainer-features%2F<id>/settings` で public に変更するようユーザーに依頼する（API では変更できない）。変更後に再実行して確認する。
2. ワークフローがドキュメント更新 PR（`automated-documentation-update-*`）を作成していれば、以下を行う。
   1. `gh pr close <PR>` の後に `gh pr reopen <PR>` を実行して CI を起動する。この PR は `GITHUB_TOKEN` で作成されるため `pull_request` のワークフローが走らず、main branch の ruleset が要求する CI のチェックが報告されないままになる。人の操作による reopen で初めてワークフローが動く。
   2. `gh pr checks <PR> --watch` で CI の完了を待つ。
   3. マージの確認を得たら `gh pr merge <PR> --merge --delete-branch` を実行し、ローカルの `main` を `git pull --ff-only` で更新する。

最後に、公開したバージョン、PR、ワークフロー実行の URL をまとめて報告する。
