param(
    [string]$JavaBinary = "java",
    [string]$DistPath = "dist",
    [int]$Iterations = 2,
    [int]$BaseBackendPort = 48010,
    [int]$PortStridePerIteration = 200,
    [int]$DelayMsBetweenRuns = 200
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($Iterations -lt 1) {
    throw "Iterations must be >= 1."
}

$tests = @(
    [PSCustomObject]@{ Name = "e2e-play-keepalive-vanilla-modern-matrix.ps1"; PortOffset = 0 },
    [PSCustomObject]@{ Name = "e2e-play-bootstrap-protocol-vanilla-modern-matrix.ps1"; PortOffset = 20 },
    [PSCustomObject]@{ Name = "e2e-play-movement-vanilla-modern-matrix.ps1"; PortOffset = 40 },
    [PSCustomObject]@{ Name = "e2e-play-input-response-vanilla-modern-matrix.ps1"; PortOffset = 70 },
    [PSCustomObject]@{ Name = "e2e-play-world-modern-matrix.ps1"; PortOffset = 90 },
    [PSCustomObject]@{ Name = "e2e-play-entity-inventory-modern-matrix.ps1"; PortOffset = 110 },
    [PSCustomObject]@{ Name = "e2e-play-combat-modern-matrix.ps1"; PortOffset = 130 },
    [PSCustomObject]@{ Name = "e2e-play-combat-lifecycle-modern-matrix.ps1"; PortOffset = 150 },
    [PSCustomObject]@{ Name = "e2e-play-extensions-vanilla-modern-matrix.ps1"; PortOffset = 170 }
)

$runCount = 0
for ($iteration = 0; $iteration -lt $Iterations; $iteration++) {
    Write-Host "[ONYX][SOAK] ITERATION_START index=$($iteration + 1)/$Iterations"
    $iterBasePort = $BaseBackendPort + ($iteration * $PortStridePerIteration)
    foreach ($test in $tests) {
        $path = Join-Path $PSScriptRoot $test.Name
        if (-not (Test-Path $path)) {
            throw "Missing soak test script: $path"
        }
        $backendPort = $iterBasePort + $test.PortOffset
        Write-Host "[ONYX][SOAK] RUN test=$($test.Name) base-port=$backendPort"
        try {
            & $path `
                -JavaBinary $JavaBinary `
                -DistPath $DistPath `
                -BaseBackendPort $backendPort
        } catch {
            throw "Soak run failed at iteration=$($iteration + 1), test=$($test.Name): $($_.Exception.Message)"
        }
        $runCount++
        if ($DelayMsBetweenRuns -gt 0) {
            Start-Sleep -Milliseconds $DelayMsBetweenRuns
        }
    }
    Write-Host "[ONYX][SOAK] ITERATION_OK index=$($iteration + 1)/$Iterations"
}

Write-Host "[ONYX] E2E_PLAY_SOAK_OK"
Write-Host "[ONYX][SOAK] ITERATIONS=$Iterations"
Write-Host "[ONYX][SOAK] TOTAL_RUNS=$runCount"
