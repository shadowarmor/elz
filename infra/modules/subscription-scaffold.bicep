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
@description('Create a pay-as-you-go Log Analytics workspace for activity-log collection.')
param deployLogAnalytics bool = false

var resourceTags = union(tags, { Environment: 'platform', LandingZone: purpose })
resource group 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: 'rg-${prefix}-${purpose}'
  location: location
  tags: resourceTags
}
module network './network.bicep' = if (deployNetwork) {
  name: '${prefix}-${purpose}-network'
  scope: group
  params: {
    name: 'vnet-${prefix}-hub'
    location: location
    addressPrefix: addressPrefix
    tags: resourceTags
  }
}
module logAnalytics './log-analytics.bicep' = if (deployLogAnalytics) {
  name: '${prefix}-${purpose}-logs'
  scope: group
  params: {
    name: 'log-${prefix}-${purpose}'
    location: location
    tags: resourceTags
  }
}
output resourceGroupId string = group.id
output virtualNetworkId string = deployNetwork ? network!.outputs.virtualNetworkId : ''
output logAnalyticsWorkspaceId string = deployLogAnalytics ? logAnalytics!.outputs.workspaceId : ''
