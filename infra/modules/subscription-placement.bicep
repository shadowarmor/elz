targetScope = 'tenant'

@description('Existing subscription GUID in the current tenant. This operation changes its parent management group.')
param subscriptionId string
@description('Existing destination management group ID without its resource path.')
param managementGroupName string

resource managementGroupResource 'Microsoft.Management/managementGroups@2023-04-01' existing = {
  name: managementGroupName
}
resource association 'Microsoft.Management/managementGroups/subscriptions@2023-04-01' = {
  parent: managementGroupResource
  name: subscriptionId
}
