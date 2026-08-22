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

$forbiddenPattern = ('AI' + 'za[0-9A-Za-z_-]{20,}') + '|' +
    ('AnyplaceSecret' + 'Key2026') + '|' +
    ('AnyplaceSalt' + '123') + '|' +
    ('AnyplacePepper' + '123')
$matches = & rg -n --hidden -i `
    -g '!**/.git/**' -g '!**/.codex-cache/**' -g '!**/node_modules/**' -g '!**/bower_components/**' -g '!**/target/**' `
    $forbiddenPattern $root
Assert-True ($LASTEXITCODE -in 0, 1) 'Could not scan the repository for secret-containment violations.'
Assert-True ($matches.Count -eq 0) "Tracked credentials or insecure secret defaults found: $($matches -join ', ')"

$service = Read-RepositoryFile 'anyplace.service'
Assert-True ($service -match 'EnvironmentFile=/etc/anyplace/anyplace\.env') 'The systemd unit must load secrets from a protected environment file.'
Assert-True ($service -match '\$\{APPLICATION_SECRET\}') 'The systemd unit must not embed an application secret.'

$installer = Read-RepositoryFile 'install.sh'
Assert-True ($installer -notmatch '\$DISP_(APP_SECRET|PLAY_SECRET|SALT|PEPPER|MONGO_PASS)') 'The installer must not print secret values.'

$userController = Read-RepositoryFile 'server/app/controllers/UserController.scala'
Assert-True ($userController -notmatch 'LOG\.D[0-9]\("(register|loginLocal|refresh): " \+ json\)') 'Authentication request bodies must not be logged.'

$controlBar = Read-RepositoryFile 'clients/web/anyplace_architect/controllers/ControlBarController.js'
Assert-True ($controlBar -notmatch 'token:" \+ cookieAccessToken') 'Browser access tokens must not be logged.'

Write-Host 'Secret-containment checks passed.'
