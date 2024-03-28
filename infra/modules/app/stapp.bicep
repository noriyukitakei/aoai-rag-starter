metadata description = 'Creates an Azure Static Web Apps instance.'
param name string
param location string = resourceGroup().location
param tags object = {}


param sku object = {
  name: 'Free'
  tier: 'Free'
}

resource stapp 'Microsoft.Web/staticSites@2021-03-01' = {
  name: name
  location: location
  tags: tags
  sku: sku
  properties: {
    provider: 'Custom'
  }
}

output name string = stapp.name
output uri string = 'https://${stapp.properties.defaultHostname}'
