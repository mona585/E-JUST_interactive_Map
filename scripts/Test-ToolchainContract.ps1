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

$contract = Read-RepositoryFile 'docs/recovery/UBUNTU_22.04_TOOLCHAIN.md'
Assert-True ($contract -match 'Ubuntu Server 22\.04 LTS') 'The Ubuntu 22.04 target is not documented.'
Assert-True ($contract -match 'OpenJDK 17') 'The required backend JDK is not documented.'
Assert-True ($contract -match 'Node\.js 22 LTS') 'The required Node.js line is not documented.'
Assert-True ($contract -match 'grunt-cli@1\.5\.0 bower@1\.8\.14') 'The legacy web CLI versions are not pinned.'

Assert-True ((Read-RepositoryFile '.sdkmanrc') -match '(?m)^java=17\.0\.19-tem$') 'SDKMAN does not select the pinned JDK.'
foreach ($scriptPath in 'install.sh', 'start.sh') {
    $script = Read-RepositoryFile $scriptPath
    Assert-True ($script -match 'java-17-openjdk-amd64') "$scriptPath does not select OpenJDK 17."
    Assert-True ($script -notmatch 'java-11-openjdk-amd64') "$scriptPath still selects OpenJDK 11."
}

$service = Read-RepositoryFile 'anyplace.service'
Assert-True ($service -match 'JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64') 'The systemd unit does not pin Java 17.'

$preflight = Read-RepositoryFile 'scripts/verify-ubuntu-toolchain.sh'
Assert-True ($preflight -match 'VERSION_ID:-.*22\.04') 'The preflight script does not enforce Ubuntu 22.04.'
Assert-True ($preflight -match 'sbt\.version=1\.5\.8') 'The preflight script does not verify SBT 1.5.8.'
Assert-True ($preflight -match 'gradle-7\.2-bin\.zip') 'The preflight script does not verify the Android Gradle wrapper.'

foreach ($app in 'anyplace_architect', 'anyplace_viewer', 'anyplace_viewer_campus') {
    Assert-True (Test-Path -LiteralPath (Join-Path $root "clients/web/$app/package-lock.json")) "Missing package lockfile for $app."
}

Write-Host 'Toolchain-contract checks passed.'
