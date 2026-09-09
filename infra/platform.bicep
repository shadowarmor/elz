targetScope = 'tenant'

@description('Organization prefix.')
param prefix string
@description('Resource location.')
param location string
@description('Connectivity / shared platform subscription.')
param connectivitySubscriptionId string
@description('Management subscription; may equal connectivity.')
param managementSubscriptionId string
@description('Identity subscription; may equal connectivity.')
param identitySubscriptionId string
@description('Security subscription; may equal connectivity.')
param securitySubscriptionId string
@description('Hub CIDR.')
param hubAddressPrefix string
@description('Common ownership and cost tags.')
param tags object
@description('Create the management Log Analytics workspace for activity-log collection.')
param deployLogAnalytics bool = false

module connectivity './modules/subscription-scaffold.bicep' = {
  name: '${prefix}-connectivity'
  scope: subscription(connectivitySubscriptionId)
  params: {
    prefix: prefix
    purpose: 'connectivity'
    location: location
    tags: tags
    deployNetwork: true
    addressPrefix: hubAddressPrefix
  }
}
// Index 0 is management; its scaffold optionally hosts the workspace.
var serviceSubscriptions = [
  { purpose: 'management', subscriptionId: managementSubscriptionId }
  { purpose: 'identity', subscriptionId: identitySubscriptionId }
  { purpose: 'security', subscriptionId: securitySubscriptionId }
]
module services './modules/subscription-scaffold.bicep' = [for item in serviceSubscriptions: {
  name: '${prefix}-${item.purpose}'
  scope: subscription(item.subscriptionId)
  params: {
    prefix: prefix
    purpose: item.purpose
    location: location
    tags: tags
    deployLogAnalytics: deployLogAnalytics && item.purpose == 'management'
  }
}]
output hubVirtualNetworkId string = connectivity.outputs.virtualNetworkId
output logAnalyticsWorkspaceId string = services[0].outputs.logAnalyticsWorkspaceId
