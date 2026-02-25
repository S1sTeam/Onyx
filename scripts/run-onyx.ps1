param(
    [string]$JavaBinary = "java",
    [string]$DistPath = "dist",
    [switch]$InitOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) {
    Write-Host "[ONYX] $Message"
}

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$dist = Join-Path $root $DistPath
$serverJar = Join-Path $dist "server.jar"

if (-not (Test-Path $serverJar)) {
    throw "Missing $serverJar. Run scripts/build-onyx.ps1 first."
}

Write-Step "Using distribution path: $dist"
Push-Location $dist
try {
    if ($InitOnly) {
        Write-Step "Generating default runtime files via one launch..."
        & $JavaBinary -jar ".\server.jar" --init-only
        if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 1) {
            Write-Step "Initialization run finished."
            exit 0
        }
        throw "Init run failed with exit code $LASTEXITCODE"
    }

    Write-Step "Starting Onyx server..."
    & $JavaBinary -jar ".\server.jar"
    if ($LASTEXITCODE -ne 0) {
        throw "Onyx server exited with code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}
