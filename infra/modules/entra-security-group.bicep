targetScope = 'tenant'
extension microsoftGraphV1

@description('Stable lowercase organization prefix.')
param prefix string
@description('Group purpose suffix used in its immutable uniqueName and display name.')
param purpose string
@description('Azure access granted to this group by the parent deployment.')
param groupDescription string
@description('Create the group when no existing object ID is supplied.')
param createGroup bool = true
@description('Existing Entra security group object ID. When supplied, group properties and membership are not modified.')
param existingGroupObjectId string = ''
@description('Explicit owner object IDs to append to newly managed groups. Empty leaves ownership to the tenant group administration process.')
@maxLength(100)
param ownerObjectIds string[] = []
@description('Explicit member object IDs to append. Empty grants no individual access; existing members are preserved.')
param memberObjectIds string[] = []

var groupName = 'sg-${prefix}-${purpose}'
resource securityGroup 'Microsoft.Graph/groups@v1.0' = if (createGroup && empty(existingGroupObjectId)) {
  uniqueName: groupName
  displayName: groupName
  description: groupDescription
  mailEnabled: false
  mailNickname: groupName
  securityEnabled: true
  // Omit isAssignableToRole: ordinary security groups support Azure RBAC and need no directory-role privilege.
  owners: {
    relationshipSemantics: 'append'
    relationships: ownerObjectIds
  }
  members: {
    relationshipSemantics: 'append'
    relationships: memberObjectIds
  }
}

output groupObjectId string = !empty(existingGroupObjectId) ? existingGroupObjectId : (createGroup ? securityGroup!.id : '')
output displayName string = groupName
output managedByTemplate bool = createGroup && empty(existingGroupObjectId)
