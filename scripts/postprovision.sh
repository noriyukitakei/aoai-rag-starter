#!/bin/bash

# Azure Developer CLIによってazd provideコマンドが実行された後に実行されるスクリプト

# Azuer Functionsをローカルで起動するための設定ファイルであるlocal.settings.jsonを作成する
# まずは、azdコマンドを使って、Azure Functionsの設定値を取得する
AOAI_ENDPOINT=$(azd env get-values 2>/dev/null | grep "^AOAI_ENDPOINT" | cut -d'=' -f2 | tr -d '"')
SEARCH_SERVICE_ENDPOINT=$(azd env get-values 2>/dev/null | grep "^SEARCH_SERVICE_ENDPOINT" | cut -d'=' -f2 | tr -d '"')
COSMOSDB_ENDPOINT=$(azd env get-values 2>/dev/null | grep "^COSMOSDB_ENDPOINT" | cut -d'=' -f2 | tr -d '"')
COSMOSDB_DATABASE=$(azd env get-values 2>/dev/null | grep "^COSMOSDB_DATABASE" | cut -d'=' -f2 | tr -d '"')
COSMOSDB_CONTAINER=$(azd env get-values 2>/dev/null | grep "^COSMOSDB_CONTAINER" | cut -d'=' -f2 | tr -d '"')
AOAI_MODEL=$(azd env get-values 2>/dev/null | grep "^AOAI_MODEL" | cut -d'=' -f2 | tr -d '"')
AOAI_GPT_35_TURBO_DEPLOYMENT=$(azd env get-values 2>/dev/null | grep "^AOAI_GPT_35_TURBO_DEPLOYMENT" | cut -d'=' -f2 | tr -d '"')
AOAI_GPT_4_DEPLOYMENT=$(azd env get-values 2>/dev/null | grep "^AOAI_GPT_4_DEPLOYMENT" | cut -d'=' -f2 | tr -d '"')
AOAI_GPT_4_32K_DEPLOYMENT=$(azd env get-values 2>/dev/null | grep "^AOAI_GPT_4_32K_DEPLOYMENT" | cut -d'=' -f2 | tr -d '"')
AOAI_TEXT_EMBEDDING_ADA_002_DEPLOYMENT=$(azd env get-values 2>/dev/null | grep "^AOAI_TEXT_EMBEDDING_ADA_002_DEPLOYMENT" | cut -d'=' -f2 | tr -d '"')
AOAI_API_VERSION=$(azd env get-values 2>/dev/null | grep "^AOAI_API_VERSION" | cut -d'=' -f2 | tr -d '"')

# local.settings.jsonのテンプレートファイルを読み込み、先程取得した設定値で置換して、local.settings.jsonを作成する
cat scripts/local.settings.json | \
sed "s|\${AOAI_ENDPOINT}|$AOAI_ENDPOINT|g" | \
sed "s|\${SEARCH_SERVICE_ENDPOINT}|$SEARCH_SERVICE_ENDPOINT|g" | \
sed "s|\${COSMOSDB_ENDPOINT}|$COSMOSDB_ENDPOINT|g" | \
sed "s|\${COSMOSDB_DATABASE}|$COSMOSDB_DATABASE|g" | \
sed "s|\${COSMOSDB_CONTAINER}|$COSMOSDB_CONTAINER|g" | \
sed "s|\${AOAI_MODEL}|$AOAI_MODEL|g" | \
sed "s|\${AOAI_GPT_35_TURBO_DEPLOYMENT}|$AOAI_GPT_35_TURBO_DEPLOYMENT|g" | \
sed "s|\${AOAI_GPT_4_DEPLOYMENT}|$AOAI_GPT_4_DEPLOYMENT|g" | \
sed "s|\${AOAI_GPT_4_32K_DEPLOYMENT}|$AOAI_GPT_4_32K_DEPLOYMENT|g" | \
sed "s|\${AOAI_TEXT_EMBEDDING_ADA_002_DEPLOYMENT}|$AOAI_TEXT_EMBEDDING_ADA_002_DEPLOYMENT|g" | \
sed "s|\${AOAI_API_VERSION}|$AOAI_API_VERSION|g" \
> ./src/backend/local.settings.json

# このスクリプトで使う環境変数をexportし、さらにインデクサーで使う環境変数を.envファイルに書き出す
echo "" > ./scripts/.env
while IFS='=' read -r key value; do
    value=$(echo "$value" | sed 's/^"//' | sed 's/"$//')
    export "$key=$value" # このスクリプトで使う環境変数をexport
    echo "$key=$value" >> ./scripts/.env # インデクサーをローカル環境で使うための環境変数を.envファイルに書き出し
done <<EOF
$(azd env get-values)
EOF

# az cliでログインしているユーザーのサービスプリンシパルIDを取得する
export AZURE_PRINCIPAL_ID=$(az ad signed-in-user show -o tsv --query id)

# Cosmos DBにアクセスするためのカスタムロールを作成し、
# Azure Functionsのシステム割り当てマネージドIDと、az cliでログインしているユーザーのサービスプリンシパルIDにそのロールを割り当てる
# カスタムロールがなければ作成する。すでにある場合はそのIDを取得する
roleId=$(az cosmosdb sql role definition list --account-name "$COSMOSDB_ACCOUNT" --resource-group "$COSMOSDB_RESOURCE_GROUP" --output tsv --query "[?roleName=='MyReadWriteRole'].id | [0]")

if [ -z "$roleId" ]; then
    roleId=$(az cosmosdb sql role definition create --account-name "$COSMOSDB_ACCOUNT" --resource-group "$COSMOSDB_RESOURCE_GROUP" --body ./scripts/cosmosreadwriterole.json --output tsv --query id)
fi
az cosmosdb sql role assignment create --account-name "$COSMOSDB_ACCOUNT" --resource-group "$COSMOSDB_RESOURCE_GROUP" --scope / --principal-id "$BACKEND_IDENTITY_PRINCIPAL_ID" --role-definition-id $roleId
az cosmosdb sql role assignment create --account-name "$COSMOSDB_ACCOUNT" --resource-group "$COSMOSDB_RESOURCE_GROUP" --scope / --principal-id "$AZURE_PRINCIPAL_ID" --role-definition-id $roleId

# インデクサーのPythonスクリプトを実行するためのPython仮想環境を作成し、依存関係をインストールする
echo 'Creating python virtual environment "scripts/.venv"'
python -m venv scripts/.venv

echo 'Installing dependencies from "requirements.txt" into virtual environment'
./scripts/.venv/bin/python -m pip install -r scripts/requirements.txt

# バックエンド(Azure Functions)を実行するためのPython仮想環境を作成する。
echo 'Creating python virtual environment "src/backend/.venv"'
python -m venv src/backend/.venv

# インデクサーを実行する
./scripts/.venv/bin/python scripts/indexer.py --docs ./data/* 