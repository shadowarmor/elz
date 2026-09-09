[CmdletBinding()]
param(
    [Parameter(Mandatory)][guid]$TenantId,
    [Parameter(Mandatory)][string]$ParametersFile,
    [string]$DeploymentLocation = 'southafricanorth',
    [ValidateSet('Validate', 'WhatIf', 'Deploy')][string]$Mode = 'WhatIf',
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
$arguments = @('deployment', 'tenant', $operation, '--name', $DeploymentName,
    '--location', $DeploymentLocation, '--template-file', (Join-Path $repo 'azuredeploy.json'),
    '--parameters', ('@' + $parameterPath), '--only-show-errors')
& az @arguments
if ($LASTEXITCODE -ne 0) { throw "Tenant deployment operation failed: $Mode" }
