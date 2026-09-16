---
name: release
description: このリポジトリの devcontainer feature をリリースする。変更のある feature を洗い出し、バージョンを上げる PR を作ってマージし、release ワークフローを実行して ghcr.io への公開を確認する。
disable-model-invocation: true
---

# devcontainer feature のリリース

引数で feature ID が指定された場合はその feature だけを対象にする。指定がなければ `src/*` 配下のすべての feature を対象にする。

各ステップで想定外の結果になった場合は、先へ進まずにユーザーに報告する。

PR のマージと公開の実行は、いずれもユーザーの確認を得てから行う。

- `gh pr merge` と `gh workflow run release.yaml` は `.claude/settings.json` の `permissions.ask` に登録してある。auto mode の分類器はこれらをレビューなしのマージ、本番デプロイとして拒否するため、ask ルールで実行時にユーザーの承認を求める。いずれも `&&` などでほかのコマンドとつながず、単独で実行する。
- `gh workflow run` には Actions の write 権限が要る。Codespaces では `.devcontainer/devcontainer.json` の `customizations.codespaces.repositories` で要求しているが、Codespace 作成時に承認していないと HTTP 403 `Resource not accessible by integration` になる。その場合は Actions 画面（`https://github.com/aetos382/devcontainer-features/actions/workflows/release.yaml`）から `main` で実行するようユーザーに依頼し、実行の連絡を受けてから手順 4.3 に進む。

## 1. 前提条件の確認

- `command -v git gh curl jq` がすべて解決すること。`jq` は Windows に標準では入っていないため、欠けていたらユーザーに報告して中断する。この 4 つ以外の外部コマンドは使わない。JSON の加工は `jq` で完結させ、`sort -V` のような GNU 拡張に依存しない。
- `git status --porcelain` が空であること。
- 現在のブランチが `main` で、`git fetch origin` の後に `origin/main` と一致していること。fetch を省略してリモート追跡参照を見ると、マージ済みの内容を未マージと誤認する。

公開そのものは release ワークフロー上の `devcontainers/action` が行い、公開後の確認は curl と jq で足りるため、ローカルに devcontainer CLI と Node.js は不要。

## 2. リリース対象の洗い出し

feature ごとに以下を取得する（feature 間は並行してよい）。

- ローカル バージョン: `jq -r .version src/<id>/devcontainer-feature.json`
- 公開済みバージョン: 後述の「公開済みタグの取得」で得たタグのうち、`X.Y.Z` 形式の最大値。
  - 通信エラーで取得できなかった場合は中断してユーザーに報告する。非公開や未公開と混同しないこと。
  - 非公開または未公開だった場合は、`gh api users/aetos382/packages/container/devcontainer-features%2F<id> --jq .visibility` で区別する。パッケージの存在確認はスコープ検査より先に行われるため、404 と 403 で区別できる。

| 応答 | 意味 | 対応 |
|---|---|---|
| 404（Package not found） | 未公開 | `初回リリース` として扱う |
| `private` | 公開済みだが非公開 | 公開済みバージョンが判定できないため中断し、public に変更するよう依頼する（手順 5.1 を参照） |
| `public` | 公開済みで public | 匿名で取得できるはずなので**想定外**。一時障害などを疑い、中断してユーザーに報告する |
| 403（`read:packages` スコープ不足） | 可視性が読めない | 非公開の可能性が高いが断定できないため、ユーザーに確認する |
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

# 非公開・未公開だけを rc=2 とし、それ以外の異常はすべて rc=1 にする。
if ! resp=$(curl -sS "https://ghcr.io/token?service=ghcr.io&scope=repository:${repo}:pull"); then
  echo "token エンドポイントへの接続に失敗" >&2; exit 1
fi
if ! printf '%s' "$resp" | jq -e . >/dev/null 2>&1; then
  printf 'token エンドポイントの応答が JSON でない: %s\n' "$resp" >&2; exit 1
fi
token=$(printf '%s' "$resp" | jq -r '.token // empty')
if [ -z "$token" ]; then
  if printf '%s' "$resp" | jq -e 'any(.errors[]?; .code == "DENIED")' >/dev/null; then
    printf '非公開または未公開: %s\n' "$resp"; exit 2
  fi
  printf 'token を取得できない想定外の応答: %s\n' "$resp" >&2; exit 1
fi
if ! body=$(curl -sS -H "Authorization: Bearer ${token}" "https://ghcr.io/v2/${repo}/tags/list"); then
  echo "tags/list への接続に失敗" >&2; exit 1
fi
if ! printf '%s' "$body" | jq -e -r '.tags[]'; then
  printf 'タグ一覧を解釈できない: %s\n' "$body" >&2; exit 1
fi
```

書き方の注意は以下のとおり。

- `curl` の応答を直接 `jq` へパイプしないこと。パイプの終了状態は末尾の `jq` で決まるため、`curl` の失敗が伝わらない。空入力の `jq -r` は成功するので、通信エラーが「タグ 0 件」や「非公開」に化ける。上のように応答をいったん変数に受け、`curl` の終了状態と JSON の内容を別々に検査する。
- `curl` に `-f` を付けないこと。エラー本文が捨てられ、非公開を示す 403 `DENIED` が読めなくなる。HTTP エラーは本文から判断し、`-f` の代わりに `curl` の終了状態で転送エラーだけを拾う。
- token が空であることを「非公開または未公開」の根拠にしないこと。応答が HTML（5xx のエラー ページなど）や壊れた JSON、`DENIED` 以外のエラー コード（429 の `TOOMANYREQUESTS` など）でも token は空になる。上のように JSON として読めるかを先に確かめ、`DENIED` が含まれる場合だけを非公開・未公開（rc=2）と判定し、それ以外は想定外（rc=1）として中断する。

`X.Y.Z` 形式の最大値は jq で取る。`sort -V` は POSIX の `sort` にはないオプションなので使わない。

```bash
printf '%s' "$body" | jq -r '[.tags[] | select(test("^[0-9]+[.][0-9]+[.][0-9]+$"))] | max_by(split(".") | map(tonumber)) // empty'
```

`max_by` に数値の配列を渡すので、`0.10.0` > `0.9.0` が正しく判定される。文字列の比較では誤る。

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
5. マージの確認を得たら `gh pr merge <PR> --merge --delete-branch` を実行し、`git switch main` の後に `git pull --ff-only` でローカルの `main` を更新する。

## 4. 公開

公開対象が 1 つ以上ある場合のみ実行する。release ワークフローは `src/` 配下のすべての feature を一括で公開し、公開済みバージョンはスキップされる。

1. `gh run list --workflow release.yaml --limit 1 --json databaseId --jq '.[0].databaseId // empty'` で dispatch 前の最新 run ID を控える。
2. 公開対象の feature とバージョンを示して確認を得たら、`gh workflow run release.yaml --ref main` を実行する。
3. `gh workflow run` は run を非同期にキューへ投入するだけで ID を返さないため、手順 1 と同じコマンドを数秒間隔で叩き、控えた ID と異なる ID が現れるのを待つ。それが今回の run。しばらく待っても現れなければユーザーに報告する。`gh run watch <ID> --exit-status` で完了を待ち、失敗したら `gh run view <ID> --log-failed` の内容を報告する。

## 5. 公開後の確認

1. 公開した各 feature について、手順 2 の「公開済みタグの取得」を再実行する。
   - 新バージョンと、メジャー・マイナーの動くタグ（`1.0.0` なら `1` と `1.0`）、`latest` が揃っていることを確認する。
   - タグが取得できず、応答が 403 `DENIED` の場合はパッケージが非公開。初回リリースでは ghcr のパッケージが既定で**非公開**になるため、`https://github.com/users/aetos382/packages/container/devcontainer-features%2F<id>/settings` で public に変更するようユーザーに依頼する（API では変更できない）。変更後に再実行して確認する。
2. ワークフローがドキュメント更新 PR（`automated-documentation-update-*`）を作成していれば、以下を行う。
   1. `gh pr close <PR>` の後に `gh pr reopen <PR>` を実行して CI を起動する。この PR は `GITHUB_TOKEN` で作成されるため `pull_request` のワークフローが走らず、main branch の ruleset が要求する CI のチェックが報告されないままになる。人の操作による reopen で初めてワークフローが動く。
   2. `gh pr checks <PR> --watch` で CI の完了を待つ。
   3. マージの確認を得たら `gh pr merge <PR> --merge --delete-branch` を実行し、ローカルの `main` を `git pull --ff-only` で更新する。

最後に、公開したバージョン、PR、ワークフロー実行の URL をまとめて報告する。
