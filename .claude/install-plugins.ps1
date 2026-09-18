#Requires -Version 7

# このリポジトリで使う Claude Code の marketplace / plugin をプロジェクト スコープでインストールする。
# devcontainer / Codespaces では post-create.sh から、ローカル（Windows を含む）では手動で実行する。
#
# .claude/settings.json をマスターとし、ここではインストール対象を列挙しない。
# 何度実行しても同じ結果になる。

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# settings.json の extraKnownMarketplaces に書いた source から、
# claude plugin marketplace add に渡す引数を組み立てる。
#
# StrictMode 下では未定義のキーを読んだ時点で落ちるが、そのメッセージにはどの marketplace が
# 悪いのかが出ない。settings.json の書き間違いを直せるようにするため、必要なキーは
# ContainsKey で確かめて、名前を添えて投げる。
function Get-MarketplaceSource {
    param (
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        $Source
    )

    if (-not $Source.ContainsKey('source')) {
        throw "Marketplace has no source type: $Name"
    }

    switch ($Source.source) {
        'github' {
            if (-not $Source.ContainsKey('repo')) {
                throw "Marketplace has no repo: $Name"
            }

            return $Source.repo
        }

        'git' {
            if (-not $Source.ContainsKey('url')) {
                throw "Marketplace has no url: $Name"
            }

            # ブランチやタグを指す marketplace は、URL の末尾に #<ref> を付けて渡す。
            # Claude Code はこれを source: git の url と ref に分けて記録するので、
            # settings.json には分かれた形で書き、ここで元の形に戻す。
            if ($Source.ContainsKey('ref')) {
                return "$($Source.url)#$($Source.ref)"
            }

            return $Source.url
        }

        default {
            # 扱えない source を黙って飛ばすと、plugin のインストールが理由の分からない失敗になる。
            throw "Unsupported marketplace source: $Name ($($Source.source))"
        }
    }
}

$settingsFile = Join-Path $PSScriptRoot 'settings.json'
$settings = Get-Content -LiteralPath $settingsFile -Raw | ConvertFrom-Json -AsHashtable

# marketplace add --scope project はカレント ディレクトリのプロジェクトに書き込むため、
# どこから実行されてもリポジトリのルートで動かす。
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    # 未定義のキーを参照すると StrictMode で失敗するので、ContainsKey で確かめてから読む。
    $marketplaces = if ($settings.ContainsKey('extraKnownMarketplaces')) { $settings.extraKnownMarketplaces } else { @{} }
    $plugins = if ($settings.ContainsKey('enabledPlugins')) { $settings.enabledPlugins } else { @{} }

    # 途中まで追加してから失敗しないよう、実行前にすべての source を解決する。
    #
    # キーは marketplace の名前で、enabledPlugins の <plugin>@<marketplace> がこれを参照する。
    # ここで渡すのは source だけなので、キーが marketplace 側の manifest にある name と
    # 食い違っていても、このスクリプトは成功したまま plugin の解決だけが失敗する。
    # settings.json に書くキーは manifest の name に合わせること。
    $sources = [ordered]@{}
    foreach ($name in $marketplaces.Keys) {
        $marketplace = $marketplaces[$name]
        if (-not $marketplace.ContainsKey('source')) {
            throw "Marketplace has no source: $name"
        }

        $sources[$name] = Get-MarketplaceSource -Name $name -Source $marketplace.source
    }

    foreach ($name in $sources.Keys) {
        claude plugin marketplace add --scope project $sources[$name]
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to add marketplace: $name (exit code $LASTEXITCODE)"
        }
    }

    foreach ($plugin in $plugins.Keys) {
        if ($plugins[$plugin] -ne $true) {
            continue
        }

        claude plugin install --scope project --yes $plugin
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to install plugin: $plugin (exit code $LASTEXITCODE)"
        }
    }
}
finally {
    Pop-Location
}
