targetScope = 'subscription'
extension microsoftGraphV1

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
@description('Optional existing Entra security group object ID granted Contributor only on the workload resource group. Blank creates a group when createSecurityGroups is true.')
param applicationTeamGroupObjectId string = ''
@description('Create the application security group if no existing group is supplied. Requires Microsoft Graph group-write privileges.')
param createSecurityGroups bool = true
@description('Owner object IDs to append to the application group created by this template. Existing groups supplied by ID are not modified.')
@maxLength(100)
param securityGroupOwnerObjectIds string[] = []
@description('Member object IDs to append to the application group created by this template. Empty preserves existing members and adds none.')
param applicationTeamMemberObjectIds string[] = []

var applicationGroupName = 'sg-${prefix}-application-${environment}-contributors'
resource applicationSecurityGroup 'Microsoft.Graph/groups@v1.0' = if (createSecurityGroups && empty(applicationTeamGroupObjectId)) {
  uniqueName: applicationGroupName
  displayName: applicationGroupName
  description: 'ELZ ${environment} application contributors: Azure Contributor on the workload resource group only.'
  mailEnabled: false
  mailNickname: applicationGroupName
  securityEnabled: true
  owners: {
    relationshipSemantics: 'append'
    relationships: securityGroupOwnerObjectIds
  }
  members: {
    relationshipSemantics: 'append'
    relationships: applicationTeamMemberObjectIds
  }
}
var effectiveApplicationGroupObjectId = !empty(applicationTeamGroupObjectId) ? applicationTeamGroupObjectId : (createSecurityGroups ? applicationSecurityGroup!.id : '')

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
module applicationContributor './modules/workload-role.bicep' = if (createSecurityGroups || !empty(applicationTeamGroupObjectId)) {
  name: '${prefix}-${environment}-team'
  scope: workloadGroup
  params: {
    principalId: effectiveApplicationGroupObjectId
  }
}
output virtualNetworkId string = network.outputs.virtualNetworkId
output workloadResourceGroupId string = workloadGroup.id
output workloadSubnetId string = network.outputs.workloadSubnetId
output privateEndpointSubnetId string = network.outputs.privateEndpointSubnetId
output applicationSecurityGroupObjectId string = effectiveApplicationGroupObjectId
