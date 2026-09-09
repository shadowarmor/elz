targetScope = 'resourceGroup'

@description('Virtual network name.')
param name string
@description('Resource region.')
param location string
@description('Network address prefix. Must be /16 to /24; reserves two /26 subnets.')
param addressPrefix string
@description('Resource tags.')
param tags object

var subnetDefinitions = [
  { name: 'snet-workload', cidr: cidrSubnet(addressPrefix, 26, 0) }
  { name: 'snet-private-endpoints', cidr: cidrSubnet(addressPrefix, 26, 1) }
]
resource nsg 'Microsoft.Network/networkSecurityGroups@2024-10-01' = [for subnet in subnetDefinitions: {
  name: 'nsg-${name}-${subnet.name}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Deny-All-Inbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Deny-All-Outbound'
        properties: {
          priority: 4096
          direction: 'Outbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}]
resource vnet 'Microsoft.Network/virtualNetworks@2024-10-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: [addressPrefix] }
    subnets: [for (subnet, i) in subnetDefinitions: {
      name: subnet.name
      properties: {
        addressPrefix: subnet.cidr
        defaultOutboundAccess: false
        privateEndpointNetworkPolicies: 'Enabled'
        networkSecurityGroup: { id: nsg[i].id }
      }
    }]
  }
}
output virtualNetworkId string = vnet.id
output workloadSubnetId string = '${vnet.id}/subnets/snet-workload'
output privateEndpointSubnetId string = '${vnet.id}/subnets/snet-private-endpoints'
