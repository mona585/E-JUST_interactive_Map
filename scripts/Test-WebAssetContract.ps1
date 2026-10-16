$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$developerIndex = Get-Content -Raw (Join-Path $root 'clients/web/developers/index.html')
$routes = Get-Content -Raw (Join-Path $root 'server/conf/routes')
$build = Get-Content -Raw (Join-Path $root 'scripts/build-web-assets.sh')
$buildSbt = Get-Content -Raw (Join-Path $root 'server/build.sbt')
$installer = Get-Content -Raw (Join-Path $root 'install.sh')

function Assert-Contains([string]$Text, [string]$Expected, [string]$Message) {
    if (-not $Text.Contains($Expected)) { throw $Message }
}

function Assert-NotContains([string]$Text, [string]$Unexpected, [string]$Message) {
    if ($Text.Contains($Unexpected)) { throw $Message }
}

Assert-Contains $developerIndex 'var BASE_URL = window.location.origin;' 'Swagger UI must use its serving origin.'
Assert-Contains $developerIndex 'url: BASE_URL + "/assets/swagger.json"' 'Swagger UI must request the generated local specification.'
Assert-NotContains $developerIndex 'ap.cs.ucy.ac.cy' 'Swagger UI must not target the legacy UCY host.'
Assert-NotContains $developerIndex 'code.jquery.com' 'Swagger UI must not need an external jQuery dependency.'
Assert-Contains $routes 'GET         /developers/*file' 'Developers static assets route is missing.'
Assert-Contains $routes 'GET /assets/*file' 'Assets route used by Swagger is missing.'
Assert-Contains $buildSbt 'swaggerRoutesFile := "api.routes"' 'Swagger generation is not configured from api.routes.'
Assert-Contains $build 'npm ci --no-audit --no-fund' 'Web build must use the locked npm dependency graph.'
Assert-Contains $build 'bower install --allow-root' 'Web build must restore Bower dependencies.'
Assert-Contains $build 'npx --no-install grunt deploy' 'Web build must invoke the project-pinned Grunt task.'
Assert-Contains $build 'test -f build/js/anyplace.min.js' 'Web build must verify JavaScript output.'
Assert-Contains $build 'test -f build/css/anyplace.min.css' 'Web build must verify CSS output.'
Assert-NotContains $build '|| true' 'Web build must fail instead of masking an asset failure.'
Assert-Contains $installer 'bash "$ROOT_DIR/scripts/build-web-assets.sh"' 'The Linux installer must invoke the fail-closed web build helper.'

foreach ($app in 'anyplace_architect', 'anyplace_viewer', 'anyplace_viewer_campus') {
    foreach ($file in 'package.json', 'package-lock.json', 'bower.json', 'Gruntfile.js', 'index.html') {
        if (-not (Test-Path (Join-Path $root "clients/web/$app/$file"))) {
            throw "$app is missing $file."
        }
    }
}

Write-Host 'PASS: web asset and Swagger source contract is intact.'
