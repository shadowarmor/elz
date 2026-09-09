targetScope = 'subscription'

@description('Organization prefix.')
param prefix string
@description('Platform service name.')
@allowed(['connectivity', 'management', 'identity', 'security'])
param purpose string
@description('Resource region.')
param location string
@description('Common tags.')
param tags object
@description('Create an isolated hub VNet.')
param deployNetwork bool = false
@description('Hub network CIDR.')
param addressPrefix string = '10.0.0.0/16'

resource group 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: 'rg-${prefix}-${purpose}'
  location: location
  tags: union(tags, { Environment: 'platform', LandingZone: purpose })
}
module network './network.bicep' = if (deployNetwork) {
  name: '${prefix}-${purpose}-network'
  scope: group
  params: {
    name: 'vnet-${prefix}-hub'
    location: location
    addressPrefix: addressPrefix
    tags: union(tags, { Environment: 'platform', LandingZone: purpose })
  }
}
output resourceGroupId string = group.id
output virtualNetworkId string = deployNetwork ? network!.outputs.virtualNetworkId : ''
