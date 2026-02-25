param(
    [string]$JavaBinary = "java",
    [string]$DistPath = "dist",
    [int]$AntiCrashBackendPort = 48966,
    [int]$AntiCrashMalformedConnections = 160,
    [int]$SoakIterations = 2,
    [int]$SoakBaseBackendPort = 48010
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$antiCrashRunner = Join-Path $PSScriptRoot "e2e-play-anti-crash.ps1"
$soakRunner = Join-Path $PSScriptRoot "e2e-play-soak.ps1"
if (-not (Test-Path $antiCrashRunner)) {
    throw "Missing anti-crash runner: $antiCrashRunner"
}
if (-not (Test-Path $soakRunner)) {
    throw "Missing soak runner: $soakRunner"
}

Write-Host "[ONYX][HARDENING] RUN anti-crash"
& $antiCrashRunner `
    -JavaBinary $JavaBinary `
    -DistPath $DistPath `
    -BackendPort $AntiCrashBackendPort `
    -MalformedConnections $AntiCrashMalformedConnections

Write-Host "[ONYX][HARDENING] RUN soak"
& $soakRunner `
    -JavaBinary $JavaBinary `
    -DistPath $DistPath `
    -Iterations $SoakIterations `
    -BaseBackendPort $SoakBaseBackendPort

Write-Host "[ONYX] E2E_PLAY_HARDENING_OK"
Write-Host "[ONYX][HARDENING] ANTI_CRASH_CONNECTIONS=$AntiCrashMalformedConnections"
Write-Host "[ONYX][HARDENING] SOAK_ITERATIONS=$SoakIterations"
