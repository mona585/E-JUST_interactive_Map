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

# R-10: generated tile/archive links must use the configured public base and
# real "/" separators, through the routed api.routes path - not a legacy
# "/anyplace/floortiles" path or OS File.separatorChar.
$tilerHelper = Read-RepositoryFile 'server/app/utils/AnyPlaceTilerHelper.scala'
Assert-True ($tilerHelper -match 'def getFloorTilesZipLinkFor[\s\S]*?api\.urlPath\("api",\s*"floortiles"') 'getFloorTilesZipLinkFor must build its link with api.urlPath(...), not string concatenation.'
Assert-True ($tilerHelper -notmatch '"/anyplace/floortiles') 'The tile link generator must not use the legacy /anyplace/floortiles path.'

$serverApi = Read-RepositoryFile 'server/app/utils/AnyplaceServerAPI.scala'
Assert-True ($serverApi -match 'val sep = "/"') 'urlPath must join path segments with a literal "/", not File.separatorChar.'
Assert-True ($serverApi -match 'def urlPath') 'AnyplaceServerAPI must expose the urlPath builder used by the tiler helper.'

# The routed upload path is uploadWithZoom() only; the deprecated 4-argument
# upload()/tileImage() path (which cannot satisfy start-anyplace-tiler.sh's
# 5-argument contract) must stay unrouted.
$routes = Read-RepositoryFile 'server/conf/api.routes'
Assert-True ($routes -match '(?m)^POST\s+/api/mapping/floor/floorplan/upload\s+controllers\.MapFloorplanController\.uploadWithZoom\(\)') 'The floorplan upload route must dispatch to uploadWithZoom().'
Assert-True ($routes -notmatch 'controllers\.MapFloorplanController\.upload\(\)') 'The deprecated 4-argument upload() action must not be routed.'

$floorplanController = Read-RepositoryFile 'server/app/controllers/MapFloorplanController.scala'
Assert-True ($floorplanController -match 'tilerHelper\.tileImageWithZoom\(') 'uploadWithZoom() must invoke tileImageWithZoom(), which supplies the zoom argument the tiler requires.'
Assert-True ($floorplanController -match 'zoom\.toInt < MIN_ZOOM_UPLOAD') 'uploadWithZoom() must reject a zoom below the minimum before tiling.'

$tilerStart = Read-RepositoryFile 'server/anyplace_tiler/start-anyplace-tiler.sh'
Assert-True ($tilerStart -match '"\$#" != "5"') 'start-anyplace-tiler.sh must still require exactly 5 arguments (documents why the deprecated 4-arg caller cannot be routed).'

# The generated GET route must match what the helper generates.
Assert-True ($routes -match '(?m)^GET\s+/api/floortiles/:buid/:floor_number/\*file\s+controllers\.MapFloorplanController\.getStaticTiles') 'The static-tile retrieval route must exist and match the generated link shape.'

# Filesystem roots stay externally configured (D-06/D-07 style), never hardcoded.
$privateConfig = Read-RepositoryFile 'server/conf/app.private.example.conf'
foreach ($key in 'floorPlansRootDir', 'radioMapRawDir', 'radioMapFrozenDir', 'tilerRootDir') {
    Assert-True ($privateConfig -match [regex]::Escape($key)) "$key must remain externally configured in the private-config template."
}

Write-Host 'Floorplan/tiler pipeline contract checks passed.'
