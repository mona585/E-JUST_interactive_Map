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

# D-05 / R-14: public registration must never auto-grant Administrator.
$userController = Read-RepositoryFile 'server/app/controllers/UserController.scala'
Assert-True ($userController -notmatch 'if\s*\(\s*pds\.db\.isAdmin\(\)\s*\)\s*\n?\s*accType\s*=\s*"admin"') 'register() must not auto-promote the first caller to admin.'
Assert-True ($userController -match 'val accType = "user"') 'register() must always assign the plain user role.'
Assert-True ($userController -notmatch 'if\s*\(\s*pds\.db\.isAdmin\(\)\s*\)\s*userType\s*=\s*"admin"') 'Google authorization must not auto-promote to admin either.'
Assert-True ($userController -match 'val userType = "user"') 'Google authorization must always assign the plain user role.'

# The only path that may create an admin account is the private, token-gated
# bootstrap endpoint, and it must fail closed on a missing/placeholder token,
# a wrong token, and on any pre-existing user.
Assert-True ($userController -match 'def bootstrapAdmin\(\)') 'A private bootstrapAdmin() action must exist.'
Assert-True ($userController -match 'X-Bootstrap-Token') 'bootstrapAdmin() must require a dedicated bootstrap-token header.'
Assert-True ($userController -match 'CHANGE_ME_ADMIN_BOOTSTRAP_TOKEN') 'bootstrapAdmin() must reject the documented placeholder token.'
Assert-True ($userController -match '"admin"\)\s*\n\s*if \(newAdmin' -or $userController -match 'register\([^)]*"admin"\)') 'bootstrapAdmin() must be the code path that assigns the admin role.'
Assert-True ($userController -match 'if \(!pds\.db\.isAdmin\(\)\)') 'bootstrapAdmin() must fail closed once any user already exists.'

$routes = Read-RepositoryFile 'server/conf/api.routes'
Assert-True ($routes -match 'POST\s+/api/user/bootstrap-admin\s+controllers\.UserController\.bootstrapAdmin\(\)') 'The bootstrap-admin route must be registered.'

$privateConfig = Read-RepositoryFile 'server/conf/app.private.example.conf'
Assert-True ($privateConfig -match 'admin\.bootstrapToken="CHANGE_ME_ADMIN_BOOTSTRAP_TOKEN"') 'The private-config template must document the bootstrap token as an explicit placeholder.'

$install = Read-RepositoryFile 'install.sh'
Assert-True ($install -match 'Admin Bootstrap Token') 'install.sh must acknowledge the bootstrap token exists without printing it.'
Assert-True ($install -notmatch 'Admin Bootstrap Token\s*:\s*\$\{GREEN\}\$') 'install.sh must never print the literal bootstrap token value.'

# Empty-baseline schema/init tooling must exist and stay idempotent (D-02).
Assert-True (Test-Path (Join-Path $root 'server/database/init_schema.js')) 'The empty-baseline schema script must exist.'
Assert-True (Test-Path (Join-Path $root 'server/database/init_database.sh')) 'The reproducible init/reset script must exist.'
$initDb = Read-RepositoryFile 'server/database/init_database.sh'
Assert-True ($initDb -match '--drop') 'init_database.sh must support an explicit disposable-drop path, never an implicit one.'

# D-10 coordinated backup: MongoDB + floorplan/radiomap filesystem roots from
# one run, with a manifest, and an isolated restore-drill path.
Assert-True (Test-Path (Join-Path $root 'server/database/admin/coordinated_backup.sh')) 'A coordinated backup script covering MongoDB + filesystem roots must exist.'
Assert-True (Test-Path (Join-Path $root 'server/database/admin/coordinated_restore_drill.sh')) 'An isolated coordinated restore-drill script must exist.'
$coordBackup = Read-RepositoryFile 'server/database/admin/coordinated_backup.sh'
foreach ($fragment in 'mongodump', 'FS_FLOORPLANS', 'FS_RADIOMAPS_RAW', 'FS_RADIOMAPS_FROZEN', 'MANIFEST.txt', 'sha256sum', 'RETENTION_DAYS') {
    Assert-True ($coordBackup -match [regex]::Escape($fragment)) "coordinated_backup.sh must reference $fragment."
}
$coordRestore = Read-RepositoryFile 'server/database/admin/coordinated_restore_drill.sh'
Assert-True ($coordRestore -match 'RESTORE_MDB_DATABASE') 'coordinated_restore_drill.sh must restore only into the disposable restore database, never the live one.'
Assert-True ($coordRestore -match 'sha256sum -c') 'coordinated_restore_drill.sh must verify manifest checksums before restoring.'

Write-Host 'Administrator-bootstrap and empty-data-baseline contract checks passed.'
