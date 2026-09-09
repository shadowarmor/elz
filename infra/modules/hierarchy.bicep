targetScope = 'tenant'

@description('Stable organization prefix.')
param prefix string
@description('Organization display name.')
param organizationName string

resource root 'Microsoft.Management/managementGroups@2023-04-01' = {
  name: prefix
  properties: {
    displayName: organizationName
    details: { parent: { id: tenantResourceId('Microsoft.Management/managementGroups', tenant().tenantId) } }
  }
}
var topGroups = [
  { suffix: 'platform', displayName: 'Platform' }
  { suffix: 'landingzones', displayName: 'Landing Zones' }
  { suffix: 'sandbox', displayName: 'Sandbox' }
  { suffix: 'decommissioned', displayName: 'Decommissioned' }
]
resource top 'Microsoft.Management/managementGroups@2023-04-01' = [for group in topGroups: {
  name: '${prefix}-${group.suffix}'
  properties: { displayName: group.displayName, details: { parent: { id: root.id } } }
}]
var platformGroups = ['connectivity', 'management', 'identity', 'security']
resource platform 'Microsoft.Management/managementGroups@2023-04-01' = [for group in platformGroups: {
  name: '${prefix}-${group}'
  properties: { displayName: '${toUpper(substring(group, 0, 1))}${substring(group, 1)}', details: { parent: { id: top[0].id } } }
}]
var applicationGroups = ['corp', 'online', 'local']
resource applications 'Microsoft.Management/managementGroups@2023-04-01' = [for group in applicationGroups: {
  name: '${prefix}-${group}'
  properties: { displayName: '${toUpper(substring(group, 0, 1))}${substring(group, 1)}', details: { parent: { id: top[1].id } } }
}]
output rootManagementGroupId string = root.id
