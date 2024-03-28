param name string
param applicationInsightsName string
param searchServiceName string
param openAiServiceName string
param openAiModelName string
param openAiApiVersion string
param openAiGpt35TurboDeploymentName string
param openAiGpt4DeploymentName string
param openAiGpt432kDeploymentName string
param location string = resourceGroup().location
param tags object = {}
param appServicePlanId string
param storageAccountName string
param webServiceUri string
param cosmosDbAccountName string
param cosmosDbDatabaseName string
param cosmosDbContainerName string

resource func 'Microsoft.Web/sites@2021-03-01' = {
  name: name
  location: location
  kind: 'functionapp,linux'
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    reserved: true
    serverFarmId: appServicePlanId
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storage.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storage.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(storageAccountName)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'
        }
        {
          name: 'SEARCH_SERVICE_ENDPOINT'
          value: 'https://${searchService.name}.search.windows.net/'
        }
        {
          name: 'AOAI_ENDPOINT'
          value: openAiService.properties.endpoint
        }
        {
          name: 'AOAI_MODEL'
          value: openAiModelName
        }
        {
          name: 'AOAI_API_VERSION'
          value: openAiApiVersion
        }
        {
          name: 'AOAI_GPT_35_TURBO_DEPLOYMENT'
          value: 'gpt-35-turbo-deploy'
        }
        {
          name: 'AOAI_GPT_4_DEPLOYMENT'
          value: 'gpt-4-deploy'
        }
        {
          name: 'AOAI_GPT_4_32K_DEPLOYMENT'
          value: 'gpt-4-32k-deploy'
        }
        {
          name: 'AOAI_TEXT_EMBEDDING_ADA_002_DEPLOYMENT'
          value: 'text-embedding-ada-002-deploy'
        }
        {
          name: 'COSMOSDB_ENDPOINT'
          value: cosmosDbAccount.properties.documentEndpoint
        }
        {
          name: 'COSMOSDB_DATABASE'
          value: cosmosDbDatabase.name
        }
        {
          name: 'COSMOSDB_CONTAINER'
          value: cosmosDbContainer.name
        }
      ]
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
      linuxFxVersion: 'Python|3.10'
      cors: {
        allowedOrigins: ['${webServiceUri}']
      }
    }
    httpsOnly: true
  }
}

// Azure Functionsのデプロイに必要な情報を渡すために、bicepで作成されたリソースの情報を取得する。
resource storage 'Microsoft.Storage/storageAccounts@2022-05-01' existing = {
  name: storageAccountName
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: applicationInsightsName
}

resource searchService 'Microsoft.Search/searchServices@2021-04-01-preview' existing = {
  name: searchServiceName
}

resource openAiService 'Microsoft.CognitiveServices/accounts@2023-10-01-preview' existing = {
  name: openAiServiceName
}

resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2021-04-15' existing = {
  name: cosmosDbAccountName
}

resource cosmosDbDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2021-04-15' existing = {
  name: cosmosDbDatabaseName
}

resource cosmosDbContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2021-04-15' existing = {
  name: cosmosDbContainerName
}

// フロントエンドのアプリにAPIのホスト名を渡すために、Azure FunctionsのURLを出力する。
output host string = func.properties.defaultHostName

// ここでAzure FunctionsのマネージドIDを出力する。
// main.bicepでこのマネージドIDを参照して、Azure AI Searchなどの各リソースにアクセス権限を与える。
output identityPrincipalId string = func.identity.principalId
