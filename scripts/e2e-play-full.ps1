param(
    [string]$JavaBinary = "java",
    [string]$DistPath = "dist",
    [string[]]$OnlyTests = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$allTests = @(
    "e2e-play-keepalive.ps1",
    "e2e-play-keepalive-timeout.ps1",
    "e2e-play-keepalive-vanilla.ps1",
    "e2e-play-keepalive-vanilla-modern.ps1",
    "e2e-play-keepalive-vanilla-modern-matrix.ps1",
    "e2e-play-bootstrap.ps1",
    "e2e-play-bootstrap-ack.ps1",
    "e2e-play-bootstrap-vanilla.ps1",
    "e2e-play-bootstrap-protocol-vanilla.ps1",
    "e2e-play-bootstrap-protocol-vanilla-modern-matrix.ps1",
    "e2e-play-bootstrap-protocol-vanilla-legacy.ps1",
    "e2e-play-movement.ps1",
    "e2e-play-movement-on-ground.ps1",
    "e2e-play-movement-vanilla-flags.ps1",
    "e2e-play-movement-vanilla-modern-matrix.ps1",
    "e2e-play-movement-vanilla-legacy.ps1",
    "e2e-play-movement-rotation.ps1",
    "e2e-play-movement-rotation-vanilla-flags.ps1",
    "e2e-play-input.ps1",
    "e2e-play-persistent.ps1",
    "e2e-play-persistent-idle-timeout.ps1",
    "e2e-play-input-response.ps1",
    "e2e-play-input-response-vanilla.ps1",
    "e2e-play-input-response-vanilla-modern-matrix.ps1",
    "e2e-play-input-response-vanilla-legacy.ps1",
    "e2e-play-command-dispatch.ps1",
    "e2e-play-chat-command-bridge.ps1",
    "e2e-play-plugin-input-hook.ps1",
    "e2e-play-plugin-command-registry.ps1",
    "e2e-play-input-rate-limit.ps1",
    "e2e-play-world.ps1",
    "e2e-play-world-modern-matrix.ps1",
    "e2e-play-continuous-world.ps1",
    "e2e-play-entity-inventory.ps1",
    "e2e-play-entity-inventory-modern-matrix.ps1",
    "e2e-play-combat.ps1",
    "e2e-play-combat-modern-matrix.ps1",
    "e2e-play-combat-lifecycle.ps1",
    "e2e-play-combat-lifecycle-modern-matrix.ps1",
    "e2e-play-extensions-vanilla-modern-matrix.ps1",
    "e2e-play-engine.ps1"
)

$selectedTests = @($allTests)
if ($OnlyTests.Count -gt 0) {
    $selectedTests = @()
    foreach ($name in $OnlyTests) {
        if ($allTests -notcontains $name) {
            throw "Unknown play test name: $name"
        }
        $selectedTests += $name
    }
}

$started = Get-Date
Write-Host "[ONYX][PLAY-FULL] START count=$($selectedTests.Count)"

foreach ($test in $selectedTests) {
    $path = Join-Path $PSScriptRoot $test
    if (-not (Test-Path $path)) {
        throw "Missing play test script: $path"
    }

    Write-Host "[ONYX][PLAY-FULL] RUN $test"
    try {
        & $path -JavaBinary $JavaBinary -DistPath $DistPath
    } catch {
        throw "Play test failed: $test :: $($_.Exception.Message)"
    }
}

$elapsed = [int][Math]::Round(((Get-Date) - $started).TotalSeconds)
Write-Host "[ONYX] E2E_PLAY_FULL_OK"
Write-Host "[ONYX][PLAY-FULL] ELAPSED_SECONDS=$elapsed"
