param(
    [string]$JavaBinary = "java",
    [string]$DistPath = "dist",
    [double]$Hours = 24.0,
    [int]$BaseBackendPort = 54000,
    [int]$PortStridePerLoop = 500,
    [int]$DelayMsBetweenLoops = 1000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($Hours -le 0) {
    throw "Hours must be > 0."
}
if ($PortStridePerLoop -lt 200) {
    throw "PortStridePerLoop must be >= 200."
}

$runner = Join-Path $PSScriptRoot "e2e-play-soak.ps1"
if (-not (Test-Path $runner)) {
    throw "Missing soak runner: $runner"
}

$start = Get-Date
$deadline = $start.AddHours($Hours)
$loop = 0
$totalRuns = 0

Write-Host "[ONYX][SOAK-DURATION] START hours=$Hours deadline=$($deadline.ToString('o'))"

while ((Get-Date) -lt $deadline) {
    $loop++
    $loopBasePort = $BaseBackendPort + (($loop - 1) * $PortStridePerLoop)
    Write-Host "[ONYX][SOAK-DURATION] LOOP_START index=$loop base-port=$loopBasePort"

    & $runner `
        -JavaBinary $JavaBinary `
        -DistPath $DistPath `
        -Iterations 1 `
        -BaseBackendPort $loopBasePort `
        -PortStridePerIteration 200 `
        -DelayMsBetweenRuns 200

    $totalRuns += 1
    Write-Host "[ONYX][SOAK-DURATION] LOOP_OK index=$loop"

    if ($DelayMsBetweenLoops -gt 0) {
        Start-Sleep -Milliseconds $DelayMsBetweenLoops
    }
}

$elapsedSeconds = [int][Math]::Round(((Get-Date) - $start).TotalSeconds)
Write-Host "[ONYX] E2E_PLAY_SOAK_DURATION_OK"
Write-Host "[ONYX][SOAK-DURATION] LOOPS=$loop"
Write-Host "[ONYX][SOAK-DURATION] ELAPSED_SECONDS=$elapsedSeconds"
