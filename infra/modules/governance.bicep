targetScope = 'managementGroup'

@description('Organization prefix used in policy and deployment names. Assignment names at management group scope are limited to 24 characters.')
@maxLength(12)
param prefix string
@description('Policy identity metadata location. Identities have no role assignments and cannot remediate resources.')
param location string
@description('Allowed regions; empty skips this assignment.')
param allowedLocations array
@description('Effect for resource guardrails.')
@allowed(['Audit', 'Deny'])
param guardrailEffect string
@description('Assign Microsoft cloud security benchmark.')
param enableMicrosoftCloudSecurityBenchmark bool
@description('Assign CIS Azure Foundations v3.0.0.')
param enableCis bool
@description('Assign NIS2.')
param enableNis2 bool
@description('Optional existing group for security visibility.')
param securityReadersGroupObjectId string

var catalog = loadJsonContent('../policy-catalog.json')
var switches = { mcsb: enableMicrosoftCloudSecurityBenchmark, cis: enableCis, nis2: enableNis2 }
var enabledInitiatives = filter(catalog.initiatives, item => switches[item.key])
resource compliance 'Microsoft.Authorization/policyAssignments@2025-03-01' = [for initiative in enabledInitiatives: {
  name: '${prefix}-${initiative.assignmentSuffix}'
  location: location
  // Required for initiatives containing DINE/modify; deliberately receives no RBAC grants.
  identity: { type: 'SystemAssigned' }
  properties: {
    displayName: initiative.displayName
    description: 'ELZ compliance assessment. No enforcement or automatic remediation; technical mappings cover only part of the standard.'
    policyDefinitionId: tenantResourceId('Microsoft.Authorization/policySetDefinitions', initiative.id)
    definitionVersion: initiative.definitionVersion
    enforcementMode: 'DoNotEnforce'
    metadata: { assignedBy: 'shadowarmor/elz', category: 'Regulatory Compliance', sourceVersion: initiative.observedVersion }
    nonComplianceMessages: [{ message: 'Review the mapped control and document or implement the required technical and organizational action.' }]
  }
}]

resource locationsDefinition 'Microsoft.Authorization/policyDefinitions@2025-03-01' = {
  name: '${prefix}-allowed-locations'
  properties: {
    displayName: 'ELZ - Allowed resource locations'
    policyType: 'Custom'
    mode: 'Indexed'
    metadata: { category: 'General', version: '1.0.0' }
    parameters: {
      allowedLocations: { type: 'Array', metadata: { displayName: 'Allowed locations', strongType: 'location' } }
      effect: { type: 'String', allowedValues: ['Audit', 'Deny'], defaultValue: 'Deny' }
    }
    policyRule: {
      if: {
        allOf: [
          { field: 'location', notIn: '[parameters(\'allowedLocations\')]' }
          { field: 'location', notEquals: 'global' }
          { field: 'type', notEquals: 'Microsoft.AzureActiveDirectory/b2cDirectories' }
        ]
      }
      then: { effect: '[parameters(\'effect\')]' }
    }
  }
}
resource locations 'Microsoft.Authorization/policyAssignments@2025-03-01' = if (!empty(allowedLocations)) {
  name: '${prefix}-locations'
  properties: {
    displayName: 'ELZ - Allowed resource locations'
    policyDefinitionId: locationsDefinition.id
    enforcementMode: 'Default'
    parameters: { allowedLocations: { value: allowedLocations }, effect: { value: guardrailEffect } }
  }
}
resource classicDefinition 'Microsoft.Authorization/policyDefinitions@2025-03-01' = {
  name: '${prefix}-no-classic'
  properties: {
    displayName: 'ELZ - Restrict classic resource providers'
    policyType: 'Custom'
    mode: 'All'
    metadata: { category: 'General', version: '1.0.0' }
    parameters: { effect: { type: 'String', allowedValues: ['Audit', 'Deny'], defaultValue: 'Deny' } }
    policyRule: {
      if: { anyOf: [
        { field: 'type', like: 'Microsoft.ClassicCompute/*' }
        { field: 'type', like: 'Microsoft.ClassicNetwork/*' }
        { field: 'type', like: 'Microsoft.ClassicStorage/*' }
      ] }
      then: { effect: '[parameters(\'effect\')]' }
    }
  }
}
resource classic 'Microsoft.Authorization/policyAssignments@2025-03-01' = {
  name: '${prefix}-no-classic'
  properties: {
    displayName: 'ELZ - Restrict classic resources'
    policyDefinitionId: classicDefinition.id
    enforcementMode: 'Default'
    parameters: { effect: { value: guardrailEffect } }
  }
}
resource tagsDefinition 'Microsoft.Authorization/policyDefinitions@2025-03-01' = {
  name: '${prefix}-resource-group-tags'
  properties: {
    displayName: 'ELZ - Audit resource group ownership and cost tags'
    policyType: 'Custom'
    mode: 'All'
    metadata: { category: 'Tags', version: '1.0.0' }
    policyRule: {
      if: {
        allOf: [
          { field: 'type', equals: 'Microsoft.Resources/subscriptions/resourceGroups' }
          { anyOf: [
            { field: 'tags[Owner]', exists: 'false' }
            { field: 'tags[CostCenter]', exists: 'false' }
            { field: 'tags[Environment]', exists: 'false' }
            { field: 'tags[Owner]', equals: '' }
            { field: 'tags[CostCenter]', equals: '' }
            { field: 'tags[Environment]', equals: '' }
          ] }
        ]
      }
      then: { effect: 'audit' }
    }
  }
}
resource tagAudit 'Microsoft.Authorization/policyAssignments@2025-03-01' = {
  name: '${prefix}-rg-tags'
  properties: {
    displayName: 'ELZ - Audit resource group ownership and cost tags'
    policyDefinitionId: tagsDefinition.id
    enforcementMode: 'Default'
  }
}
var securityRoles = ['acdd72a7-3385-48ef-bd42-f606fba81ae7', '39bc4728-0917-49c7-9d2c-d95423bc2eb4']
module securityReaders './group-role.bicep' = [for (roleId, i) in securityRoles: if (!empty(securityReadersGroupObjectId)) {
  name: '${prefix}-security-reader-${i}'
  params: { principalId: securityReadersGroupObjectId, roleDefinitionId: roleId }
}]
output complianceAssignmentIds array = [for (initiative, i) in enabledInitiatives: compliance[i].id]
