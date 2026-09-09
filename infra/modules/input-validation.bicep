targetScope = 'tenant'
@description('Must be true: each explicitly supplied subscription GUID must be unique. Use blanks to share platform services.')
@allowed([true])
param subscriptionIdsAreDistinct bool
@description('Must be true: every supplied subscription ID, group object ID, owner ID, and member ID must be a hyphenated GUID (8-4-4-4-12).')
@allowed([true])
param identifiersAreGuids bool
@description('Must be true: organizationPrefix must begin with a letter and contain only letters, digits, and hyphens.')
@allowed([true])
param organizationPrefixIsValid bool
@description('Must be true: allowedLocations must be empty or contain the resource location.')
@allowed([true])
param resourceRegionIsAllowed bool
@description('Must be true: networks must use RFC1918 IPv4 space with prefixes /16 to /24.')
@allowed([true])
param networksArePrivateAndSized bool
@description('Must be true: CIDRs must use the network address, without host bits set.')
@allowed([true])
param networksAreCanonical bool
@description('Must be true: the hub and application address ranges must not overlap.')
@allowed([true])
param networksDoNotOverlap bool
output valid bool = subscriptionIdsAreDistinct && identifiersAreGuids && organizationPrefixIsValid && resourceRegionIsAllowed && networksArePrivateAndSized && networksAreCanonical && networksDoNotOverlap
