targetScope = 'resourceGroup'
@description('Existing application team Entra group object ID.')
param principalId string
resource assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, principalId, 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  properties: {
    principalId: principalId
    principalType: 'Group'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  }
}
