param name string
param location string = resourceGroup().location
param tags object = {}

resource hostingPlan 'Microsoft.Web/serverfarms@2021-03-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
    size: 'Y1'
    family: 'Y'
    capacity: 0
  }
  properties: {
    reserved: true
  }
}

output id string = hostingPlan.id
