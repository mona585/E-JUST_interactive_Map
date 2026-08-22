# E-JUST Interactive Map — Dev Environment Launcher
# Run this script to start all development services

$env:JAVA_HOME = "D:\programing\jdk-17"
$env:PATH = "D:\programing\jdk-17\bin;D:\programing\sbt\bin;" + $env:PATH

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   E-JUST Interactive Map — Dev Launcher   " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# Check MongoDB
$mongo = Get-Service "MongoDB" -ErrorAction SilentlyContinue
if ($mongo.Status -ne "Running") {
    Write-Host "[MongoDB] Starting service..." -ForegroundColor Yellow
    Start-Service MongoDB
} else {
    Write-Host "[MongoDB] Already running ✓" -ForegroundColor Green
}

Write-Host ""
Write-Host "Starting services in separate windows..." -ForegroundColor White
Write-Host ""

# Start backend in new window
Write-Host "[Backend]  Starting Scala/Play server on http://localhost:9000 ..." -ForegroundColor Yellow
Start-Process powershell -ArgumentList "-NoExit", "-Command", "
    `$env:JAVA_HOME = 'D:\programing\jdk-17';
    `$env:PATH = 'D:\programing\jdk-17\bin;D:\programing\sbt\bin;' + `$env:PATH;
    Set-Location 'C:\Users\20101\Desktop\Ejust\server';
    Write-Host 'Starting backend... (first run downloads deps, ~10-15 min)' -ForegroundColor Yellow;
    sbt run
"

Start-Sleep -Seconds 3

# Start Architect frontend
Write-Host "[Architect] Starting Architect web app on http://localhost:3000 ..." -ForegroundColor Yellow
Start-Process powershell -ArgumentList "-NoExit", "-Command", "
    `$env:PATH = (npm root -g) + ';' + `$env:PATH;
    serve 'C:\Users\20101\Desktop\Ejust\clients\web\anyplace_architect' -p 3000
"

Start-Sleep -Seconds 2

# Start Viewer frontend
Write-Host "[Viewer]   Starting Viewer web app on http://localhost:3001 ..." -ForegroundColor Yellow
Start-Process powershell -ArgumentList "-NoExit", "-Command", "
    serve 'C:\Users\20101\Desktop\Ejust\clients\web\anyplace_viewer_campus' -p 3001
"

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Services starting in separate windows:   " -ForegroundColor Cyan
Write-Host "   Backend API:  http://localhost:9000     " -ForegroundColor Green
Write-Host "   Architect:    http://localhost:3000     " -ForegroundColor Green
Write-Host "   Viewer:       http://localhost:3001     " -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "NOTE: Backend takes 10-15 min on first run" -ForegroundColor Yellow
Write-Host "      (downloads Scala/Play dependencies)  " -ForegroundColor Yellow
