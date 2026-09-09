[CmdletBinding()]
param([switch]$Check)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
Push-Location $repo
try {
    $targets = @{
        'infra/main.bicep' = 'azuredeploy.json'
        'infra/application.bicep' = 'application.azuredeploy.json'
    }
    foreach ($entry in $targets.GetEnumerator()) {
        $temporary = Join-Path ([System.IO.Path]::GetTempPath()) ('elz-' + [guid]::NewGuid() + '.json')
        try {
            az bicep build --file $entry.Key --outfile $temporary
            if ($LASTEXITCODE -ne 0) { throw "Bicep build failed: $($entry.Key)" }
            if ($Check) {
                if (!(Test-Path -LiteralPath $entry.Value)) { throw "Missing compiled template: $($entry.Value)" }
                $expected = (Get-Content -Raw -LiteralPath $entry.Value).Replace("`r`n", "`n").Trim()
                $actual = (Get-Content -Raw -LiteralPath $temporary).Replace("`r`n", "`n").Trim()
                if ($expected -ne $actual) { throw "Stale compiled template: $($entry.Value). Run scripts/build.ps1 with Bicep 0.47.16." }
            } else {
                Copy-Item -LiteralPath $temporary -Destination $entry.Value
            }
        } finally {
            if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
        }
    }
    python -m unittest discover -s tests -v
    if ($LASTEXITCODE -ne 0) { throw 'Template checks failed.' }
} finally { Pop-Location }
