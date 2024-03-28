# Azure Developer CLIによってazd provideコマンドが実行された後に実行されるスクリプト

# Azure Functionsをローカルで起動するための設定ファイルであるlocal.settings.jsonを作成する
# まずは、azdコマンドを使って、Azure Functionsの設定値を取得する
$AOAI_ENDPOINT = (azd env get-values | Select-String "^AOAI_ENDPOINT.+").Matches.Value.Split('=')[1].Trim('"')
$SEARCH_SERVICE_ENDPOINT = (azd env get-values | Select-String "^SEARCH_SERVICE_ENDPOINT.+").Matches.Value.Split('=')[1].Trim('"')
$COSMOSDB_ENDPOINT = (azd env get-values | Select-String "^COSMOSDB_ENDPOINT.+").Matches.Value.Split('=')[1].Trim('"')
$COSMOSDB_DATABASE = (azd env get-values | Select-String "^COSMOSDB_DATABASE.+").Matches.Value.Split('=')[1].Trim('"')
$COSMOSDB_CONTAINER = (azd env get-values | Select-String "^COSMOSDB_CONTAINER.+").Matches.Value.Split('=')[1].Trim('"')
$AOAI_MODEL = (azd env get-values | Select-String "^AOAI_MODEL.+").Matches.Value.Split('=')[1].Trim('"')
$AOAI_GPT_35_TURBO_DEPLOYMENT = (azd env get-values | Select-String "^AOAI_GPT_35_TURBO_DEPLOYMENT.+").Matches.Value.Split('=')[1].Trim('"')
$AOAI_GPT_4_DEPLOYMENT = (azd env get-values | Select-String "^AOAI_GPT_4_DEPLOYMENT.+").Matches.Value.Split('=')[1].Trim('"')
$AOAI_GPT_4_32K_DEPLOYMENT = (azd env get-values | Select-String "^AOAI_GPT_4_32K_DEPLOYMENT.+").Matches.Value.Split('=')[1].Trim('"')
$AOAI_TEXT_EMBEDDING_ADA_002_DEPLOYMENT = (azd env get-values | Select-String "^AOAI_TEXT_EMBEDDING_ADA_002_DEPLOYMENT.+").Matches.Value.Split('=')[1].Trim('"')
$AOAI_API_VERSION = (azd env get-values | Select-String "^AOAI_API_VERSION.+").Matches.Value.Split('=')[1].Trim('"')

# local.settings.jsonのテンプレートファイルを読み込み、先程取得した設定値で置換して、local.settings.jsonを作成する
(Get-Content scripts\local.settings.json) `
    -replace '\${AOAI_ENDPOINT}', $AOAI_ENDPOINT `
    -replace '\${SEARCH_SERVICE_ENDPOINT}', $SEARCH_SERVICE_ENDPOINT `
    -replace '\${COSMOSDB_ENDPOINT}', $COSMOSDB_ENDPOINT `
    -replace '\${COSMOSDB_DATABASE}', $COSMOSDB_DATABASE `
    -replace '\${COSMOSDB_CONTAINER}', $COSMOSDB_CONTAINER `
    -replace '\${AOAI_MODEL}', $AOAI_MODEL `
    -replace '\${AOAI_GPT_35_TURBO_DEPLOYMENT}', $AOAI_GPT_35_TURBO_DEPLOYMENT `
    -replace '\${AOAI_GPT_4_DEPLOYMENT}', $AOAI_GPT_4_DEPLOYMENT `
    -replace '\${AOAI_GPT_4_32K_DEPLOYMENT}', $AOAI_GPT_4_32K_DEPLOYMENT `
    -replace '\${AOAI_TEXT_EMBEDDING_ADA_002_DEPLOYMENT}', $AOAI_TEXT_EMBEDDING_ADA_002_DEPLOYMENT `
    -replace '\${AOAI_API_VERSION}', $AOAI_API_VERSION |
    Out-File -FilePath .\src\backend\local.settings.json

# このスクリプトで使う環境変数をexportし、さらにインデクサーで使う環境変数を.envファイルに書き出す
$envValues = azd env get-values
"" | Out-File -FilePath .\scripts\.env
$envValues -split "`r`n" | ForEach-Object {
    $key, $value = $_.Split('=')
    $value = $value.Trim('"')
    Set-Item -Path env:$key -Value $value
    "$key=$value" | Out-File -FilePath .\scripts\.env -Append
}

# az cliでログインしているユーザーのサービスプリンシパルIDを取得する
$AZURE_PRINCIPAL_ID = az ad signed-in-user show --output tsv --query id

# Cosmos DBにアクセスするためのカスタムロールを作成し、
# Azure Functionsのシステム割り当てマネージドIDと、az cliでログインしているユーザーのサービスプリンシパルIDにそのロールを割り当てる
# Cosmos DBのカスタムロールがなければ作成する。すでにある場合はそのIDを取得する
$roleId = az cosmosdb sql role definition list --account-name $env:COSMOSDB_ACCOUNT --resource-group $env:COSMOSDB_RESOURCE_GROUP --output tsv --query "[?roleName=='MyReadWriteRole'].id | [0]"

if (-not $roleId) {
    $roleId = az cosmosdb sql role definition create --account-name $env:COSMOSDB_ACCOUNT --resource-group $env:COSMOSDB_RESOURCE_GROUP --body ./scripts/cosmosreadwriterole.json --output tsv --query id
}

az cosmosdb sql role assignment create --account-name $env:COSMOSDB_ACCOUNT --resource-group $env:COSMOSDB_RESOURCE_GROUP --scope / --principal-id $env:BACKEND_IDENTITY_PRINCIPAL_ID --role-definition-id $roleId
az cosmosdb sql role assignment create --account-name $env:COSMOSDB_ACCOUNT --resource-group $env:COSMOSDB_RESOURCE_GROUP --scope / --principal-id $AZURE_PRINCIPAL_ID --role-definition-id $roleId

# インデクサーのPythonスクリプトを実行するためのPython仮想環境を作成し、依存関係をインストールする
Write-Host 'Creating python virtual environment "scripts/.venv"'
python -m venv .\scripts\.venv

Write-Host 'Installing dependencies from "requirements.txt" into virtual environment'
.\scripts\.venv\Scripts\python -m pip install -r .\scripts\requirements.txt

# バックエンド(Azure Functions)を実行するためのPython仮想環境を作成する。
Write-Host 'Creating python virtual environment "src/backend/.venv"'
python -m venv .\src\backend\.venv

# インデクサーを実行する
.\scripts\.venv\Scripts\python .\scripts\indexer.py --docs .\data\*

