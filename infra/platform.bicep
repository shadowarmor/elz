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
  }
}]
output hubVirtualNetworkId string = connectivity.outputs.virtualNetworkId
