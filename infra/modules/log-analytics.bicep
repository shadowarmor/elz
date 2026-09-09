targetScope = 'resourceGroup'

@description('Workspace name.')
param name string
@description('Resource region.')
param location string
@description('Resource tags.')
param tags object

// Pay-as-you-go workspace with no standing charge. Activity-log ingestion is free and the
// AzureActivity table keeps 90 days at no charge; other data sent here later is billed per GB.
// https://learn.microsoft.com/azure/azure-monitor/platform/activity-log#log-analytics-workspace
resource workspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
    features: { enableLogAccessUsingOnlyResourcePermissions: true }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}
output workspaceId string = workspace.id
