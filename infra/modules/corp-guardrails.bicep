targetScope = 'managementGroup'
@description('Organization prefix used in policy resource names. Assignment names at management group scope are limited to 24 characters.')
@maxLength(12)
param prefix string
@description('Audit or deny creation of public IP resources in corporate subscriptions.')
@allowed(['Audit', 'Deny'])
param effect string = 'Deny'
resource definition 'Microsoft.Authorization/policyDefinitions@2025-03-01' = {
  name: '${prefix}-corp-no-public-ip'
  properties: {
    displayName: 'ELZ Corp - Restrict public IP resources'
    description: 'Corp networks use centrally managed connectivity. This does not cover public endpoints on PaaS services.'
    policyType: 'Custom'
    mode: 'All'
    metadata: { category: 'Network', version: '1.0.0' }
    parameters: { effect: { type: 'String', allowedValues: ['Audit', 'Deny'], defaultValue: 'Deny' } }
    policyRule: {
      if: { field: 'type', in: ['Microsoft.Network/publicIPAddresses', 'Microsoft.Network/publicIPPrefixes'] }
      then: { effect: '[parameters(\'effect\')]' }
    }
  }
}
resource assignment 'Microsoft.Authorization/policyAssignments@2025-03-01' = {
  name: '${prefix}-corp-no-pip'
  properties: {
    displayName: 'ELZ Corp - Restrict public IP resources'
    policyDefinitionId: definition.id
    enforcementMode: 'Default'
    parameters: { effect: { value: effect } }
    nonComplianceMessages: [{ message: 'Use approved platform connectivity or an Online landing zone for public IP resources.' }]
  }
}
