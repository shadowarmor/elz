[CmdletBinding()]
param(
    [Parameter(Mandatory)][guid]$TenantId,
    [Parameter(Mandatory)][string]$ParametersFile,
    [string]$DeploymentLocation = 'southafricanorth',
    [ValidateSet('Validate', 'WhatIf', 'Deploy')][string]$Mode = 'Validate',
    [string]$DeploymentName = 'elz'
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$parameterPath = (Resolve-Path -LiteralPath $ParametersFile).Path
$account = az account show --output json --only-show-errors | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $account.tenantId -ne $TenantId.ToString()) {
    throw "Log in first: az login --tenant $TenantId"
}
python (Join-Path $PSScriptRoot 'preflight.py') --parameters $parameterPath
if ($LASTEXITCODE -ne 0) { throw 'Preflight failed.' }
$operation = @{ Validate = 'validate'; WhatIf = 'what-if'; Deploy = 'create' }[$Mode]
if ($Mode -eq 'WhatIf') {
    Write-Warning 'Microsoft Graph resources are not supported by ARM what-if. This operation may fail or omit group changes; it is not a preview of group membership or permissions.'
}
$arguments = @('deployment', 'tenant', $operation, '--name', $DeploymentName,
    '--location', $DeploymentLocation, '--template-file', (Join-Path $repo 'azuredeploy.json'),
    '--parameters', ('@' + $parameterPath), '--only-show-errors')
& az @arguments
if ($LASTEXITCODE -ne 0) { throw "Tenant deployment operation failed: $Mode" }
