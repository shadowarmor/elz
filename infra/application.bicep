targetScope = 'subscription'

@description('Organization/workload prefix. Use a unique value to vend additional landing zones within a subscription.')
@minLength(2)
@maxLength(12)
param prefix string = 'elz'
@description('Resource region.')
param location string = 'southafricanorth'
@description('Application environment.')
@allowed(['prod', 'nonprod'])
param environment string = 'prod'
@description('Non-overlapping private IPv4 CIDR, /16 to /24.')
param addressPrefix string = '10.10.0.0/16'
@description('Common tags. Include Owner and CostCenter when deploying standalone.')
param tags object = { Owner: 'application-team', CostCenter: 'applications', ManagedBy: 'Bicep', Project: 'elz' }
@description('Optional Entra group object ID granted Contributor only on the workload resource group.')
param applicationTeamGroupObjectId string = ''

var resourceTags = union(tags, { Environment: environment, LandingZone: 'application' })
resource networkGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: 'rg-${prefix}-${environment}-network'
  location: location
  tags: resourceTags
}
resource workloadGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: 'rg-${prefix}-${environment}-workload'
  location: location
  tags: resourceTags
}
module network './modules/network.bicep' = {
  name: '${prefix}-${environment}-network'
  scope: networkGroup
  params: {
    name: 'vnet-${prefix}-${environment}'
    location: location
    addressPrefix: addressPrefix
    tags: resourceTags
  }
}
module applicationContributor './modules/workload-role.bicep' = if (!empty(applicationTeamGroupObjectId)) {
  name: '${prefix}-${environment}-team'
  scope: workloadGroup
  params: {
    principalId: applicationTeamGroupObjectId
  }
}
output virtualNetworkId string = network.outputs.virtualNetworkId
output workloadResourceGroupId string = workloadGroup.id
output workloadSubnetId string = network.outputs.workloadSubnetId
output privateEndpointSubnetId string = network.outputs.privateEndpointSubnetId
