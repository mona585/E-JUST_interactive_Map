[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Read-RepositoryFile {
    param([string]$RelativePath)
    Get-Content -LiteralPath (Join-Path $root $RelativePath) -Raw
}

$applicationSpec = Read-RepositoryFile 'server/test/ApplicationSpec.scala'
Assert-True ($applicationSpec -match 'version JSON without authentication') 'The public version contract is missing.'
Assert-True ($applicationSpec -notmatch 'mapping/space/public') 'Mongo-backed space access must not be presented as a default unit test.'

Assert-True (-not (Test-Path -LiteralPath (Join-Path $root 'server/test/IntegrationSpec.scala'))) 'The obsolete browser starter-page test is still present.'
Assert-True (-not (Test-Path -LiteralPath (Join-Path $root 'server/test/DatabaseBaselineSpec.scala'))) 'The obsolete public-first-admin test is still present.'

$securitySpec = Read-RepositoryFile 'server/test/SecurityRegressionSpec.scala'
Assert-True ($securitySpec -match 'RUN_MONGO_INTEGRATION_TESTS') 'Mongo-backed regression tests must require explicit opt-in.'

$testConfig = Read-RepositoryFile 'server/test/resources/application.conf'
Assert-True ($testConfig -match '\$\{\?MONGODB_TEST_PASSWORD\}') 'Test database credentials must come from the protected environment.'
Assert-True ($testConfig -match 'analytics\.enabled = false') 'Analytics must remain disabled in tests.'

Write-Host 'Backend test-baseline checks passed.'
