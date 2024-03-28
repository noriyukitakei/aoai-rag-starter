# PowerShell

# フロントエンドアプリケーションがビルドされる前に実行されるスクリプト

# フロントエンドエンドアプリケーション内に埋め込むバックエンドAPIのエンドポイントを取得し、
# .env.productionファイルに書き出す。この環境変数はビルドされたフロントエンドアプリケーション内で使われる。
$API_ENDPOINT = (azd env get-values 2>$null | Select-String "^API_ENDPOINT" | ForEach-Object { $_ -replace '^API_ENDPOINT=', '' -replace '"', '' })
"VITE_API_ENDPOINT=$API_ENDPOINT" | Out-File -FilePath .env.production