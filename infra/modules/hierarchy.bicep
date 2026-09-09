targetScope = 'tenant'

@description('Stable organization prefix.')
param prefix string
@description('Organization display name.')
param organizationName string
@description('Set the tenant default management group for new subscriptions to Sandbox and require authorization to create management groups under the tenant root. False leaves tenant hierarchy settings untouched.')
param configureHierarchySettings bool = false

resource tenantRoot 'Microsoft.Management/managementGroups@2023-04-01' existing = {
  name: tenant().tenantId
}
resource root 'Microsoft.Management/managementGroups@2023-04-01' = {
  name: prefix
  properties: {
    displayName: organizationName
    details: { parent: { id: tenantRoot.id } }
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
// CAF recommendations: new subscriptions land in Sandbox instead of the tenant root, and only
// principals with write access on the tenant root can create management groups there.
// https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-area/resource-org-management-groups
resource hierarchySettings 'Microsoft.Management/managementGroups/settings@2023-04-01' = if (configureHierarchySettings) {
  parent: tenantRoot
  name: 'default'
  properties: {
    defaultManagementGroup: top[2].id // Sandbox
    requireAuthorizationForGroupCreation: true
  }
}
output rootManagementGroupId string = root.id
output sandboxManagementGroupId string = top[2].id
