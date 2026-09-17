#Requires -Version 7

# このリポジトリで使う Claude Code の marketplace / plugin をプロジェクト スコープでインストールする。
# devcontainer / Codespaces では post-create.sh から、ローカル（Windows を含む）では手動で実行する。
#
# .claude/settings.json をマスターとし、ここではインストール対象を列挙しない。
# 何度実行しても同じ結果になる。

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$settingsFile = Join-Path $PSScriptRoot 'settings.json'
$settings = Get-Content -LiteralPath $settingsFile -Raw | ConvertFrom-Json -AsHashtable

# marketplace add --scope project はカレント ディレクトリのプロジェクトに書き込むため、
# どこから実行されてもリポジトリのルートで動かす。
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    # 未定義のキーを参照すると StrictMode で失敗するので、ContainsKey で確かめてから読む。
    $marketplaces = if ($settings.ContainsKey('extraKnownMarketplaces')) { $settings.extraKnownMarketplaces } else { @{} }
    $plugins = if ($settings.ContainsKey('enabledPlugins')) { $settings.enabledPlugins } else { @{} }

    # github 以外の source は扱えないので、黙って飛ばさずにエラーにする。
    # 途中まで追加してから失敗しないよう、実行前にすべて確かめる。
    foreach ($name in $marketplaces.Keys) {
        $source = $marketplaces[$name].source
        if ($source.source -ne 'github') {
            throw "Unsupported marketplace source: $name ($($source.source))"
        }
    }

    foreach ($name in $marketplaces.Keys) {
        claude plugin marketplace add --scope project $marketplaces[$name].source.repo
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
