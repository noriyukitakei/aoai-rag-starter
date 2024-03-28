param name string
param location string = resourceGroup().location
param tags object = {}
param publicNetworkAccess string = 'Enabled'
param customSubDomainName string = name
param sku object = {
  name: 'S0'
}
param kind string
param deployments array = []

resource aisa 'Microsoft.CognitiveServices/accounts@2023-10-01-preview' = {
  name: name
  location: location
  tags: tags
  sku: sku
  kind: kind
  properties: {
    customSubDomainName: customSubDomainName
    networkAcls: {
      defaultAction: 'Allow'
    }
    publicNetworkAccess: publicNetworkAccess
  }
}

@batchSize(1)
resource deployment 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = [for deployment in deployments: {
  parent: aisa
  name: deployment.name
  properties: {
    model: deployment.model
    raiPolicyName: contains(deployment, 'raiPolicyName') ? deployment.raiPolicyName : null
  }
  sku: contains(deployment, 'sku') ? deployment.sku : {
    name: 'Standard'
    capacity: 20
  }
}]

output name string = aisa.name
output endpoint string = aisa.properties.endpoint
