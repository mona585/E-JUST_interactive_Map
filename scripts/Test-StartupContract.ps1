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

$privateConfig = Read-RepositoryFile 'server/conf/app.private.example.conf'
foreach ($name in 'MONGODB_HOST', 'MONGODB_PORT', 'MONGODB_DATABASE', 'MONGODB_USERNAME', 'MONGODB_PASSWORD') {
    Assert-True ($privateConfig -match "\$\{$name\}") "The private configuration does not require $name."
}

$environment = Read-RepositoryFile 'server/.env.example'
Assert-True ($environment -match '(?m)^MONGODB_HOST=127\.0\.0\.1$') 'The MongoDB host must default to loopback.'
Assert-True ($environment -match 'MONGODB_USERNAME=CHANGE_ME_') 'MongoDB credentials must be explicit placeholders.'

$service = Read-RepositoryFile 'anyplace.service'
Assert-True ($service -match '(?m)^User=anyplace$') 'The service must use the dedicated account.'
Assert-True ($service -match '(?m)^WorkingDirectory=/opt/anyplace$') 'The service must use the canonical application path.'
Assert-True ($service -match 'EnvironmentFile=/etc/anyplace/anyplace\.env') 'The service must use protected runtime configuration.'
Assert-True ($service -notmatch 'mesba7|E-JUST_interactive_Map|docker\.service') 'The service must not retain personal paths or Docker dependency.'

foreach ($scriptPath in 'start.sh', 'install.sh') {
    $script = Read-RepositoryFile $scriptPath
    Assert-True ($script -notmatch 'docker run.*-p 27017:27017') "$scriptPath can publish MongoDB publicly."
}

$start = Read-RepositoryFile 'start.sh'
Assert-True ($start -match 'MONGODB_HOST must be a loopback address') 'Interactive startup must reject a remote MongoDB host.'
Assert-True ($start -match 'MONGODB_USERNAME MONGODB_PASSWORD') 'Interactive startup must require MongoDB credentials.'

$anyplace = Read-RepositoryFile 'server/app/Anyplace.scala'
Assert-True ($anyplace -match 'analytics\.enabled.*getOrElse\(false\)') 'Analytics must remain disabled by default.'

Write-Host 'Startup-contract checks passed.'
