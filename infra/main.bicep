targetScope = 'tenant'
// Declare Graph at the root as well as in the child module so authentication reaches nested deployments.
// https://github.com/Azure/bicep/issues/19207
extension microsoftGraphV1

@description('Short lowercase organization prefix, 2-12 letters/digits/hyphens; start with a letter. Keep stable on redeployment.')
@minLength(2)
@maxLength(12)
param organizationPrefix string = 'elz'

@description('Human-readable organization name for the intermediate root management group.')
@minLength(1)
@maxLength(64)
param organizationName string = 'Enterprise Landing Zone'

@description('Azure region for resource groups and networks. The portal deployment location independently stores deployment metadata.')
param location string = 'southafricanorth'

@description('REQUIRED: existing empty subscription GUID in this tenant for connectivity and shared platform services.')
@minLength(36)
@maxLength(36)
param platformSubscriptionId string

@description('REQUIRED: a DIFFERENT existing empty subscription GUID in this tenant for the production application landing zone.')
@minLength(36)
@maxLength(36)
param applicationSubscriptionId string

@description('Optional separate management subscription GUID. Blank places management resource groups in the platform subscription.')
param managementSubscriptionId string = ''

@description('Optional separate identity subscription GUID. Blank places identity resource groups in the platform subscription.')
param identitySubscriptionId string = ''

@description('Optional separate security subscription GUID. Blank places security resource groups in the platform subscription.')
param securitySubscriptionId string = ''

@description('Optional DIFFERENT subscription GUID for a nonproduction application landing zone.')
param nonproductionSubscriptionId string = ''

@description('Application archetype. Corp denies public IP resources by default; Online supports future public-facing workloads.')
@allowed(['corp', 'online'])
param applicationArchetype string = 'corp'

@description('Platform hub IPv4 CIDR, /16 to /24. Must not overlap any application VNet; subnets are calculated automatically.')
param hubAddressPrefix string = '10.0.0.0/16'

@description('Production application IPv4 CIDR, /16 to /24. Must not overlap hub or other application networks.')
param applicationAddressPrefix string = '10.10.0.0/16'

@description('Nonproduction application IPv4 CIDR, /16 to /24. Must not overlap hub or other application networks.')
param nonproductionAddressPrefix string = '10.20.0.0/16'

@description('Non-secret ownership label placed in the Owner tag.')
@minLength(1)
param owner string = 'platform-team'

@description('Cost allocation label placed in the CostCenter tag.')
@minLength(1)
param costCenter string = 'shared-services'

@description('Optional allowed Azure resource regions, including location above. Empty disables the location guardrail; global resources are exempt.')
param allowedLocations array = []

@description('Guardrails audit or deny: allowed regions, classic resources, and Corp public IPs. Compliance initiatives always evaluate with DoNotEnforce.')
@allowed(['Audit', 'Deny'])
param guardrailEffect string = 'Deny'

@description('Assign the Microsoft cloud security benchmark (successor to Azure Security Benchmark).')
param enableMicrosoftCloudSecurityBenchmark bool = true

@description('Assign the CIS Azure Foundations v3.0.0 built-in initiative.')
param enableCis bool = true

@description('Assign the NIS2 built-in initiative. Assignment is evidence gathering, not certification or legal compliance.')
param enableNis2 bool = true

@description('Create missing Entra security groups and assign their Azure RBAC roles. Requires Entra group-write privileges in addition to Azure Owner.')
param createSecurityGroups bool = true

@description('Owner object IDs to append to groups created by ELZ. Existing groups supplied by ID are not modified. Owners can manage membership and therefore access.')
@maxLength(100)
param securityGroupOwnerObjectIds string[] = []

@description('Optional member object-ID arrays keyed by platformAdmins, securityReaders, applicationProd, applicationNonprod. Members are appended; omitted/empty lists preserve existing membership. Existing groups supplied by ID are not modified.')
param securityGroupMembers object = {}

@description('Optional existing Entra security GROUP object ID receiving Contributor at Platform. Blank creates sg-<prefix>-platform-admins when createSecurityGroups is true.')
param platformAdminsGroupObjectId string = ''

@description('Optional existing Entra security GROUP object ID receiving Reader and Security Reader at the intermediate root. Blank creates sg-<prefix>-security-readers.')
param securityReadersGroupObjectId string = ''

@description('Optional existing Entra security GROUP object ID receiving Contributor on the production workload resource group. Blank creates sg-<prefix>-application-prod-contributors.')
param applicationTeamGroupObjectId string = ''

@description('Optional existing Entra security GROUP object ID for the nonproduction workload resource group. Blank creates a separate nonproduction group when that landing zone is enabled.')
param nonproductionApplicationTeamGroupObjectId string = ''

var prefix = toLower(organizationPrefix)
var tags = {
  Owner: owner
  CostCenter: costCenter
  ManagedBy: 'Bicep'
  Project: 'elz'
}
var sharedPlatform = empty(managementSubscriptionId) || empty(identitySubscriptionId) || empty(securitySubscriptionId)
var platformPlacements = concat([
  {
    subscriptionId: platformSubscriptionId
    managementGroupName: '${prefix}-${sharedPlatform ? 'platform' : 'connectivity'}'
  }
], empty(managementSubscriptionId) ? [] : [{ subscriptionId: managementSubscriptionId, managementGroupName: '${prefix}-management' }], empty(identitySubscriptionId) ? [] : [{ subscriptionId: identitySubscriptionId, managementGroupName: '${prefix}-identity' }], empty(securitySubscriptionId) ? [] : [{ subscriptionId: securitySubscriptionId, managementGroupName: '${prefix}-security' }])
var placements = concat(platformPlacements, [
  { subscriptionId: applicationSubscriptionId, managementGroupName: '${prefix}-${applicationArchetype}' }
], empty(nonproductionSubscriptionId) ? [] : [{ subscriptionId: nonproductionSubscriptionId, managementGroupName: '${prefix}-${applicationArchetype}' }])

var subscriptionIds = map(placements, item => toLower(item.subscriptionId))
// ARM validates dependency IDs before omitting condition=false deployments.
// Keep the disabled module's scope valid; its condition still prevents any nonproduction resources.
var nonproductionDeploymentSubscriptionId = empty(nonproductionSubscriptionId) ? applicationSubscriptionId : nonproductionSubscriptionId
var cidrs = concat([hubAddressPrefix, applicationAddressPrefix], empty(nonproductionSubscriptionId) ? [] : [nonproductionAddressPrefix])
var parsedNetworks = map(cidrs, cidr => parseCidr(cidr))
// Convert IPv4 endpoints to integers for overlap checks. Invalid CIDRs/IPv6 fail evaluation before hierarchy creation.
var numericNetworks = map(parsedNetworks, net => {
  start: int(split(net.network, '.')[0]) * 16777216 + int(split(net.network, '.')[1]) * 65536 + int(split(net.network, '.')[2]) * 256 + int(split(net.network, '.')[3])
  end: int(split(net.broadcast, '.')[0]) * 16777216 + int(split(net.broadcast, '.')[1]) * 65536 + int(split(net.broadcast, '.')[2]) * 256 + int(split(net.broadcast, '.')[3])
})
module inputValidation './modules/input-validation.bicep' = {
  name: '${prefix}-validate-inputs'
  params: {
    // any defers the singleton true type check to ARM; false fails the nested deployment before mutations.
    subscriptionIdsAreDistinct: any(length(union(subscriptionIds, subscriptionIds)) == length(subscriptionIds))
    organizationPrefixIsValid: any(contains('abcdefghijklmnopqrstuvwxyz', substring(prefix, 0, 1)) && length(filter(range(0, length(prefix)), i => !contains('abcdefghijklmnopqrstuvwxyz0123456789-', substring(prefix, i, 1)))) == 0)
    resourceRegionIsAllowed: any(empty(allowedLocations) || contains(allowedLocations, location))
    networksArePrivateAndSized: any(length(filter(parsedNetworks, net => net.cidr < 16 || net.cidr > 24 || !(startsWith(net.network, '10.') || startsWith(net.network, '192.168.') || (startsWith(net.network, '172.') && int(split(net.network, '.')[1]) >= 16 && int(split(net.network, '.')[1]) <= 31)))) == 0)
    networksAreCanonical: any(length(filter(range(0, length(cidrs)), i => split(cidrs[i], '/')[0] != parsedNetworks[i].network)) == 0)
    networksDoNotOverlap: any(length(filter(range(0, length(numericNetworks)), i => length(filter(range(0, i), j => numericNetworks[i].start <= numericNetworks[j].end && numericNetworks[j].start <= numericNetworks[i].end)) > 0)) == 0)
  }
}

module hierarchy './modules/hierarchy.bicep' = {
  name: '${prefix}-hierarchy'
  params: {
    prefix: prefix
    organizationName: organizationName
  }
  dependsOn: [inputValidation]
}

var groupDefinitions = [
  { key: 'platformAdmins', purpose: 'platform-admins', existingId: platformAdminsGroupObjectId, enabled: true, description: 'ELZ platform administrators: Azure Contributor on the Platform management group.' }
  { key: 'securityReaders', purpose: 'security-readers', existingId: securityReadersGroupObjectId, enabled: true, description: 'ELZ security readers: Azure Reader and Security Reader on the organization management group.' }
  { key: 'applicationProd', purpose: 'application-prod-contributors', existingId: applicationTeamGroupObjectId, enabled: true, description: 'ELZ production application contributors: Azure Contributor on the production workload resource group only.' }
  { key: 'applicationNonprod', purpose: 'application-nonprod-contributors', existingId: nonproductionApplicationTeamGroupObjectId, enabled: !empty(nonproductionSubscriptionId), description: 'ELZ nonproduction application contributors: Azure Contributor on the nonproduction workload resource group only.' }
]
module securityGroups './modules/entra-security-group.bicep' = [for (group, i) in groupDefinitions: {
  name: '${prefix}-security-group-${i}'
  params: {
    prefix: prefix
    purpose: group.purpose
    groupDescription: group.description
    createGroup: createSecurityGroups && group.enabled
    existingGroupObjectId: group.existingId
    ownerObjectIds: securityGroupOwnerObjectIds
    memberObjectIds: securityGroupMembers[?group.key] ?? []
  }
  dependsOn: [inputValidation]
}]

module placement './modules/subscription-placement.bicep' = [for (item, i) in placements: {
  name: '${prefix}-placement-${i}'
  params: {
    subscriptionId: item.subscriptionId
    managementGroupName: item.managementGroupName
  }
  dependsOn: [hierarchy]
}]

module platform './platform.bicep' = {
  name: '${prefix}-platform'
  params: {
    prefix: prefix
    location: location
    connectivitySubscriptionId: platformSubscriptionId
    managementSubscriptionId: empty(managementSubscriptionId) ? platformSubscriptionId : managementSubscriptionId
    identitySubscriptionId: empty(identitySubscriptionId) ? platformSubscriptionId : identitySubscriptionId
    securitySubscriptionId: empty(securitySubscriptionId) ? platformSubscriptionId : securitySubscriptionId
    hubAddressPrefix: hubAddressPrefix
    tags: tags
  }
  dependsOn: [placement]
}

module application './application.bicep' = {
  name: '${prefix}-application-prod'
  scope: subscription(applicationSubscriptionId)
  params: {
    prefix: prefix
    location: location
    environment: 'prod'
    addressPrefix: applicationAddressPrefix
    tags: tags
    applicationTeamGroupObjectId: securityGroups[2].outputs.groupObjectId
    createSecurityGroups: false
  }
  dependsOn: [placement]
}

module nonproduction './application.bicep' = if (!empty(nonproductionSubscriptionId)) {
  name: '${prefix}-application-nonprod'
  scope: subscription(nonproductionDeploymentSubscriptionId)
  params: {
    prefix: prefix
    location: location
    environment: 'nonprod'
    addressPrefix: nonproductionAddressPrefix
    tags: tags
    applicationTeamGroupObjectId: securityGroups[3].outputs.groupObjectId
    createSecurityGroups: false
  }
  dependsOn: [placement]
}

// Governance follows bootstrap resources, avoiding propagation races during initial setup.
module governance './modules/governance.bicep' = {
  name: '${prefix}-governance'
  scope: managementGroup(prefix)
  params: {
    location: location
    allowedLocations: allowedLocations
    guardrailEffect: guardrailEffect
    enableMicrosoftCloudSecurityBenchmark: enableMicrosoftCloudSecurityBenchmark
    enableCis: enableCis
    enableNis2: enableNis2
    securityReadersGroupObjectId: securityGroups[1].outputs.groupObjectId
  }
  dependsOn: [platform, application, nonproduction]
}

module corpGuardrails './modules/corp-guardrails.bicep' = {
  name: '${prefix}-corp-guardrails'
  scope: managementGroup('${prefix}-corp')
  params: { effect: guardrailEffect }
  dependsOn: [governance]
}

module platformRbac './modules/group-role.bicep' = if (createSecurityGroups || !empty(platformAdminsGroupObjectId)) {
  name: '${prefix}-platform-rbac'
  scope: managementGroup('${prefix}-platform')
  params: {
    principalId: securityGroups[0].outputs.groupObjectId
    roleDefinitionId: 'b24988ac-6180-42a0-ab88-20f7382dd24c'
  }
  dependsOn: [hierarchy]
}

output rootManagementGroupId string = hierarchy.outputs.rootManagementGroupId
output subscriptionPlacement array = placements
output platformHubVirtualNetworkId string = platform.outputs.hubVirtualNetworkId
output applicationVirtualNetworkId string = application.outputs.virtualNetworkId
output applicationWorkloadResourceGroupId string = application.outputs.workloadResourceGroupId
output nonproductionVirtualNetworkId string = !empty(nonproductionSubscriptionId) ? nonproduction!.outputs.virtualNetworkId : ''
output complianceAssignmentIds array = governance.outputs.complianceAssignmentIds
output securityGroupObjectIds object = {
  platformAdmins: securityGroups[0].outputs.groupObjectId
  securityReaders: securityGroups[1].outputs.groupObjectId
  applicationProd: securityGroups[2].outputs.groupObjectId
  applicationNonprod: !empty(nonproductionSubscriptionId) ? securityGroups[3].outputs.groupObjectId : ''
}
output scaffoldNotice string = 'Security groups and Azure RBAC are included. No paid runtime services, peering, egress, central logging, Conditional Access, PIM, or automatic policy remediation are provisioned. See docs/operations.md before deploying workloads.'
