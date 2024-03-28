param name string
param location string = resourceGroup().location
param sku object = {}
param tags object = {}

resource storageAccount 'Microsoft.Storage/storageAccounts@2022-05-01' = {
  name: name
  location: location
  sku: sku
  kind: 'Storage'
  tags: tags
  properties: {
    supportsHttpsTrafficOnly: true
    defaultToOAuthAuthentication: true
  }
}

output name string = storageAccount.name
