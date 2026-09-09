targetScope = 'subscription'

@description('Organization prefix used in the diagnostic setting name.')
param prefix string
@description('Log Analytics workspace resource ID receiving this subscription\'s activity log. May live in another subscription of the same tenant.')
param workspaceId string

var categories = ['Administrative', 'Security', 'ServiceHealth', 'Alert', 'Recommendation', 'Policy', 'Autoscale', 'ResourceHealth']
// 2021-05-01-preview is the version Microsoft documents for subscription activity-log settings; the older GA
// version the linter proposes predates workspace-based activity-log export.
#disable-next-line use-recent-api-versions
resource activityLog 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${prefix}-activity-log'
  properties: {
    workspaceId: workspaceId
    logs: [for category in categories: { category: category, enabled: true }]
  }
}
output diagnosticSettingId string = activityLog.id
