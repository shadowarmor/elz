using './main.bicep'
// Replace GUIDs before deploying. These zero GUIDs deliberately fail the CLI preflight.
param organizationPrefix = 'elz'
param location = 'southafricanorth'
param platformSubscriptionId = '00000000-0000-0000-0000-000000000000'
param applicationSubscriptionId = '00000000-0000-0000-0000-000000000000'
