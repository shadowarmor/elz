targetScope = 'managementGroup'
@description('Existing Entra group object ID.')
param principalId string
@description('Built-in role definition GUID.')
param roleDefinitionId string
resource assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(managementGroup().id, principalId, roleDefinitionId)
  properties: {
    principalId: principalId
    principalType: 'Group'
    roleDefinitionId: tenantResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
  }
}
