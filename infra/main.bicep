targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

// 各リソースのリソース名を定義する。ここで何も定義されていなければ、リソース名は自動生成される。
param resourceGroupName string = '' // ここで指定されたリソースグループ名に各リソースが所属する
param webServiceName string = '' // フロントエンドのアプリをデプロイするAzure Static Web Appsの名前
param webServiceLocation string = 'eastus2' // フロントエンドのアプリをデプロイするAzure Static Web Appsのリージョン(特に指定がなければazd upコマンド実施の際に指定されたリージョンとなる)
//param webServiceLocation string = location
param apiServiceName string = '' // バックエンドのAPIをデプロイするAzure Functionsの名前
param apiServiceLocation string = '' // バックエンドのAPIをデプロイするAzure Functionsのリージョン(特に指定がなければazd upコマンド実施の際に指定されたリージョンとなる)
param storageServiceSkuName string = '' // ストレージアカウントのSKU名(特に指定がなければStandard_LRSとなる)
param searchServiceLocation string = '' // Azure AI Searchのリージョン(特に指定がなければazd upコマンド実施の際に指定されたリージョンとなる)
param searchServiceName string = '' // Azure AI Searchのリソース名
param searchServiceSkuName string = '' // Azure AI SearchのSKU名(特に指定がなければstandardとなる)
param formRecognizerServiceName string = '' // Document Intelligenceのリソース名
param formRecognizerSkuName string = '' // Document IntelligenceのSKU名(特に指定がなければS0となる)
param formRecognizerLocation string = '' // Document Intelligenceのリージョン(特に指定がなければazd upコマンド実施の際に指定されたリージョンとなる)
param openAiServiceName string = '' // Azure OpenAI Serviceのリソース名
param openAiSkuName string = '' // Azure OpenAI ServiceのSKU名(特に指定がなければS0となる)
param openAiServiceLocation string= '' // Azure OpenAI Serviceのリージョン(特に指定がなければazd upコマンド実施の際に指定されたリージョンとなる)
param openAiModelName string = '' // Azure OpenAI Serviceのモデル名(特に指定がなければgpt-35-turboとなる)
param openAiGpt35TurboDeploymentName string = 'gpt-35-turbo-deploy' // Azure OpenAI Serviceのgpt-35-turboのデプロイメント名
param openAiGpt4DeploymentName string = 'gpt-4-deploy' // Azure OpenAI Serviceのgpt-4のデプロイメント名
param openAiGpt432kDeploymentName string = 'gpt-4-32k-deploy' // Azure OpenAI Serviceのgpt-4-32kのデプロイメント名
param openAiTextEmbeddingAda002DeploymentName string = 'text-embedding-ada-002-deploy' // Azure OpenAI Serviceのtext-embedding-ada-002のデプロイメント名
param openAiApiVersion string = '2023-12-01-preview' // Azure OpenAI ServiceのAPIバージョン
param applicationInsightsServiceLocation string = '' // Application Insightsのリージョン(特に指定がなければazd upコマンド実施の際に指定されたリージョンとなる)
param cosmosDbDatabaseName string = 'ChatHistory' // Cosmos DBのデータベース名
param cosmosDbContainerName string = 'Prompts' // Cosmos DBのコンテナ名
param cosmosDbLocation string = '' // Cosmos DBのリージョン(特に指定がなければazd upコマンド実施の際に指定されたリージョンとなる)

// az cliでログインした際のユーザーのプリンシパルIDを指定する。
// ローカルで動かす場合に、az cliでログインしているユーザーに権限を与えるために利用する。
param principalId string = ''

// リソース名などに利用する一意の識別子を生成する。
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))

// タグを定義する。ここで定義されたタグは、すべてのリソースに付与される。
var tags = { 'azd-env-name': environmentName }

// Cloud Adoption Frameworkのリソース命名規則に準じた省略語を読み込む。
var abbrs = loadJsonContent('./abbreviations.json')

// リソースグループを作成する
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}


// RAGのフロントエンドアプリをデプロイするためのAzure Static Web Appsを作成する。
module web './modules/app/stapp.bicep' = {
  name: 'web'
  scope: rg
  params: {
    name: !empty(webServiceName) ? webServiceName : '${abbrs.webStaticSites}${resourceToken}'
    location: !empty(webServiceLocation) ? webServiceLocation : location
    // このタグは、Azure Devloper CLIのazd-service-nameタグを使って、リソースを特定するために使われる。
    // キーがazd-service-name、値がwebというタグの付与されているリソースにフロントエンドのアプリがデプロイされる。
    tags: union(tags, { 'azd-service-name': 'web' })
  }
}

// RAGのバックエンドAPIをデプロイするためのAzure Functionsを作成する。
module api './modules/app/func.bicep' = {
  name: 'api'
  scope: rg
  params: {
    name: !empty(apiServiceName) ? apiServiceName : '${abbrs.webSitesFunctions}${resourceToken}'
    location: !empty(apiServiceLocation) ? apiServiceLocation : location
    webServiceUri: web.outputs.uri
    appServicePlanId: appServicePlan.outputs.id
    // func.bicepでいろんなリソースのリソース情報を取得するために各リソースの名前を渡す。
    searchServiceName: searchService.outputs.name 
    openAiServiceName: openAi.outputs.name
    openAiModelName: !empty(openAiModelName) ? openAiModelName : 'gpt-35-turbo'
    openAiApiVersion: openAiApiVersion
    openAiGpt35TurboDeploymentName: openAiGpt35TurboDeploymentName
    openAiGpt4DeploymentName: openAiGpt4DeploymentName
    openAiGpt432kDeploymentName: openAiGpt432kDeploymentName
    storageAccountName: storage.outputs.name
    cosmosDbAccountName: cosmosDb.outputs.name
    cosmosDbDatabaseName: cosmosDb.outputs.databaseName
    cosmosDbContainerName: cosmosDb.outputs.containerName    
    applicationInsightsName: applicationInsights.outputs.name
    // このタグは、Azure Devloper CLIのazd-service-nameタグを使って、リソースを特定するために使われる。
    // キーがazd-service-name、値がapiというタグの付与されているリソースにバックエンドのAPIがデプロイされる。
    tags: union(tags, { 'azd-service-name': 'api' })
  }
}

// Azure FunctionsのApp Service Planを作成する。
module appServicePlan './modules/app/asp.bicep' = {
  name: 'appServicePlan'
  scope: rg
  params: {
    name: '${abbrs.webServerFarms}${resourceToken}'
    location: !empty(apiServiceLocation) ? apiServiceLocation : location

    tags: tags
  }
}

// Azure Functionsに必要なストレージアカウントを作成する。
module storage './modules/storage/storage.bicep' = {
  name: 'storage'
  scope: rg
  params: {
    name: '${abbrs.storageStorageAccounts}${resourceToken}'
    location: !empty(searchServiceLocation) ? searchServiceLocation : location
    sku: {
      // このパラメータは、ストレージアカウントのSKU名を指定する。
      // 特に指定がなければStandard_LRSとなる。
      name: !empty(storageServiceSkuName) ? storageServiceSkuName : 'Standard_LRS'
    }
    tags: tags
  }
}

// Azure Functionsのログ出力に必要なApplication Insightsを作成する。
module applicationInsights './modules/monitor/appi.bicep' = {
  name: 'appinsights'
  scope: rg
  params: {
    name: '${abbrs.insightsComponents}${resourceToken}'
    location: !empty(applicationInsightsServiceLocation) ? applicationInsightsServiceLocation : location
    tags: tags
  }
}

// Azure AI Searchを作成する。
module searchService './modules/ai/srch.bicep' = {
  name: 'search-service'
  scope: rg
  params: {
    name: !empty(searchServiceName) ? searchServiceName : '${abbrs.searchSearchServices}${resourceToken}'
    location: !empty(searchServiceLocation) ? searchServiceLocation : location
    tags: tags
    authOptions: {
      aadOrApiKey: {
        aadAuthFailureMode: 'http401WithBearerChallenge'
      }
    }
    sku: {
      // このパラメータは、Azure AI SearchのSKU名を指定する。
      // 特に指定がなければstandardとなる。
      name: !empty(searchServiceSkuName) ? searchServiceSkuName : 'standard'
    }
    semanticSearch: 'free'
  }
}

// Document Intelligenceを作成する。
module documentIntelligence './modules/ai/cognitiveservices.bicep' = {
  name: 'documentintelligence'
  scope: rg
  params: {
    name: !empty(formRecognizerServiceName) ? formRecognizerServiceName : '${abbrs.cognitiveServicesFormRecognizer}${resourceToken}'
    kind: 'FormRecognizer'
    location: !empty(formRecognizerLocation) ? formRecognizerLocation : location
    tags: tags
    sku: {
      // このパラメータは、Document IntelligenceのSKU名を指定する。
      // 特に指定がなければS0となる。
      name: !empty(formRecognizerSkuName) ? formRecognizerSkuName : 'S0'
    }
  }
} 

// Azure OpenAI Serviceを作成する。
module openAi './modules/ai/cognitiveservices.bicep' = {
  name: 'openai'
  scope: rg
  params: {
    name: !empty(openAiServiceName) ? openAiServiceName : '${abbrs.cognitiveServicesAccounts}${resourceToken}'
    kind: 'OpenAI'
    location: !empty(openAiServiceLocation) ? openAiServiceLocation : location
    tags: tags
    sku: {
      // このパラメータは、Azure OpenAI ServiceのSKU名を指定する。
      // 特に指定がなければS0となる。
      name: !empty(openAiSkuName) ? openAiSkuName : 'S0'
    }
    // Azure OpenAI Serviceのモデルをデプロイする。現時点では最も汎用的なモデルであるgpt-35-turboをデプロイする。
    // また、ベクトル検索に利用するためのtext-embedding-ada-002もデプロイする。
    deployments: [
      {
        name: 'gpt-35-turbo-deploy'
        model: {
          format: 'OpenAI'
          name: 'gpt-35-turbo'
          version: '0613'
        }
        sku: {
          name: 'Standard'
          capacity: 80
        }
      }
      {
        name: 'gpt-4-deploy'
        model: {
          format: 'OpenAI'
          name: 'gpt-4'
          version: '0613'
        }
        sku: {
          name: 'Standard'
          capacity: 10
        }
      }
      {
        name: 'gpt-4-32k-deploy'
        model: {
          format: 'OpenAI'
          name: 'gpt-4-32k'
          version: '0613'
        }
        sku: {
          name: 'Standard'
          capacity: 20
        }
      }
      {
        name: 'text-embedding-ada-002-deploy'
        model: {
          format: 'OpenAI'
          name: 'text-embedding-ada-002'
          version: '2'
        }
        sku: {
          name: 'Standard'
          capacity: 80
        }
      }
    ]
  }
}

// Cosmos DBを作成する。
module cosmosDb './modules/db/cosmosdb.bicep' = {
  name: 'cosmosdb'
  scope: rg
  params: {
    name: '${abbrs.documentDBDatabaseAccounts}${resourceToken}'
    location: !empty(cosmosDbLocation) ? cosmosDbLocation : location
    tags: union(tags, { 'azd-service-name': 'cosmosdb' })
    cosmosDbDatabaseName: cosmosDbDatabaseName
    cosmosDbContainerName: cosmosDbContainerName
  }
}

// ローカルで動かす場合に、az cliでログインしているユーザーに権限を与えるためのロールを定義する。
// Azure OpenAI ServiceのAPIを発行するために、データプレーンへのアクセス権を与える。
module openAiRoleUser './modules/security/role.bicep' = {
  scope: rg
  name: 'openai-role-user'
  params: {
    principalId: principalId
    roleDefinitionId: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
    principalType: 'User'
  }
}

// ローカルで動かす場合に、az cliでログインしているユーザーに権限を与えるためのロールを定義する。
// Azure AI Searchのインデックスを閲覧するために、データプレーンへのアクセス権を与える。
module searchRoleUser './modules/security/role.bicep' = {
  scope: rg
  name: 'search-role-user'
  params: {
    principalId: principalId
    roleDefinitionId: '1407120a-92aa-4202-b7e9-c0e197c71c8f'
    principalType: 'User'
  }
}

// ローカルで動かす場合に、az cliでログインしているユーザーに権限を与えるためのロールを定義する。
// Document IntelligenceのAPIを発行するために、データプレーンへのアクセス権を与える。
module formRecognizerRoleUser './modules/security/role.bicep' = {
  scope: rg
  name: 'formrecognizer-role-user'
  params: {
    principalId: principalId
    roleDefinitionId: 'a97b65f3-24c7-4388-baec-2e87135dc908'
    principalType: 'User'
  }
}

// ローカルで動かす場合に、az cliでログインしているユーザーに権限を与えるためのロールを定義する。
// Azure AI Searchにインデックスを登録するために、データプレーンへのアクセス権を与える。
// この権限はインデクサーで利用する。
module searchContribRoleUser './modules/security/role.bicep' = {
  scope: rg
  name: 'search-contrib-role-user'
  params: {
    principalId: principalId
    roleDefinitionId: '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
    principalType: 'User'
  }
}

// Azure上で動かす場合に必要なマネージドIDに権限を与えるためのロールを定義する。
// Azure OpenAI ServiceのAPIを発行するために、データプレーンへのアクセス権を与える。
module openAiRoleBackend './modules/security/role.bicep' = {
  scope: rg
  name: 'openai-role-managed-identity'
  params: {
    principalId: api.outputs.identityPrincipalId
    roleDefinitionId: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
    principalType: 'ServicePrincipal'
  }
}

// Azure上で動かす場合に必要なマネージドIDに権限を与えるためのロールを定義する。
// Azure AI SearchのAPIを発行するために、データプレーンへのアクセス権を与える。
module searchRoleBackend './modules/security/role.bicep' = {
  scope: rg
  name: 'search-role-managed-identity'
  params: {
    principalId: api.outputs.identityPrincipalId
    roleDefinitionId: '1407120a-92aa-4202-b7e9-c0e197c71c8f'
    principalType: 'ServicePrincipal'
  }
}

// 以降でoutputで定義される変数は環境変数として出力される。

// フロントエンドのアプリをデプロイするときにAPIのエンドポイントを埋め込む必要がある。
// そのため、APIのエンドポイントを出力する。
var API_HOST = api.outputs.host
output API_ENDPOINT string = 'https://${API_HOST}'

// バックエンドのAPIやインデクサーで必要な各リソースのエンドポイントやデータベース名、コンテナ名などを出力する。
output AOAI_ENDPOINT string = openAi.outputs.endpoint
output SEARCH_SERVICE_ENDPOINT string = searchService.outputs.endpoint
output COSMOSDB_ENDPOINT string = cosmosDb.outputs.endpoint
output COSMOSDB_DATABASE string = cosmosDb.outputs.databaseName
output COSMOSDB_CONTAINER string = cosmosDb.outputs.containerName
output COSMOSDB_ACCOUNT string = cosmosDb.outputs.accountName
output COSMOSDB_RESOURCE_GROUP string = rg.name
output AOAI_MODEL string = !empty(openAiModelName) ? openAiModelName : 'gpt-4'
output AOAI_GPT_35_TURBO_DEPLOYMENT string = openAiGpt35TurboDeploymentName
output AOAI_GPT_4_DEPLOYMENT string = openAiGpt4DeploymentName
output AOAI_GPT_4_32K_DEPLOYMENT string = openAiGpt432kDeploymentName
output AOAI_TEXT_EMBEDDING_ADA_002_DEPLOYMENT string = openAiTextEmbeddingAda002DeploymentName
output AOAI_API_VERSION string = openAiApiVersion
output DOCUMENT_INTELLIGENCE_ENDPOINT string = documentIntelligence.outputs.endpoint

// Azure Cosmos DBにAzure Functionsがアクセスするためのカスタムロールの作成が必要になる。
// その作成したカスタムロールの権限の付与先となるマネージドIDを出力する。
output BACKEND_IDENTITY_PRINCIPAL_ID string = api.outputs.identityPrincipalId
