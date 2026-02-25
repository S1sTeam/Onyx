param(
    [string]$JavaBinary = "java",
    [string]$DistPath = "dist",
    [int]$Protocol = 774,
    [int]$BaseBackendPort = 52000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($Protocol -lt 47) {
    throw "Protocol must be >= 47."
}

$disconnectPacketId = if ($Protocol -ge 773) { 0x20 } elseif ($Protocol -ge 770) { 0x1C } else { 0x1D }
$bootstrapInitPacketId = if ($Protocol -ge 773) { 0x30 } elseif ($Protocol -ge 770) { 0x2B } else { 0x2C }
$bootstrapSpawnPacketId = if ($Protocol -ge 773) { 0x46 } elseif ($Protocol -ge 770) { 0x41 } else { 0x42 }
$bootstrapMessagePacketId = if ($Protocol -ge 773) { 0x77 } elseif ($Protocol -ge 770) { 0x72 } else { 0x73 }

function Invoke-Step([string]$name, [scriptblock]$action) {
    Write-Host "[ONYX][FINISHED-V1] RUN $name"
    try {
        & $action
    } catch {
        throw "Step failed: $name :: $($_.Exception.Message)"
    }
}

$selfDir = $PSScriptRoot

Invoke-Step "build" {
    & (Join-Path $selfDir "build-onyx.ps1")
}
Invoke-Step "init" {
    & (Join-Path $selfDir "run-onyx.ps1") -JavaBinary $JavaBinary -DistPath $DistPath -InitOnly
}
Invoke-Step "configure-finished-v1" {
    & (Join-Path $selfDir "configure-finished-v1.ps1") -DistPath $DistPath -ProtocolVersion $Protocol
}

Invoke-Step "login-protocol-lock" {
    & (Join-Path $selfDir "e2e-login-protocol-lock.ps1") `
        -JavaBinary $JavaBinary `
        -DistPath $DistPath `
        -BackendPort ($BaseBackendPort + 0) `
        -AllowedProtocol $Protocol `
        -RejectedProtocol ($Protocol - 1)
}

Invoke-Step "proxy-routing" {
    & (Join-Path $selfDir "e2e-proxy-routing.ps1") -JavaBinary $JavaBinary -DistPath $DistPath
}
Invoke-Step "proxy-failover" {
    & (Join-Path $selfDir "e2e-proxy-failover.ps1") -JavaBinary $JavaBinary -DistPath $DistPath
}
Invoke-Step "forwarding-auth" {
    & (Join-Path $selfDir "e2e-forwarding-auth.ps1") -JavaBinary $JavaBinary -DistPath $DistPath
}

Invoke-Step "play-bootstrap-vanilla-locked" {
    & (Join-Path $selfDir "e2e-play-bootstrap-protocol-vanilla.ps1") `
        -JavaBinary $JavaBinary `
        -DistPath $DistPath `
        -BackendPort ($BaseBackendPort + 20) `
        -Protocol $Protocol `
        -DisconnectPacketId $disconnectPacketId `
        -BootstrapInitPacketId $bootstrapInitPacketId `
        -BootstrapSpawnPacketId $bootstrapSpawnPacketId `
        -BootstrapMessagePacketId $bootstrapMessagePacketId
}
Invoke-Step "play-world-vanilla-locked" {
    & (Join-Path $selfDir "e2e-play-world.ps1") `
        -JavaBinary $JavaBinary `
        -DistPath $DistPath `
        -BackendPort ($BaseBackendPort + 40) `
        -Protocol $Protocol `
        -DisconnectPacketId $disconnectPacketId `
        -PlayProtocolMode "vanilla" `
        -ExpectedUsername "WorldV1"
}
Invoke-Step "play-entity-inventory-vanilla-locked" {
    & (Join-Path $selfDir "e2e-play-entity-inventory.ps1") `
        -JavaBinary $JavaBinary `
        -DistPath $DistPath `
        -BackendPort ($BaseBackendPort + 60) `
        -Protocol $Protocol `
        -DisconnectPacketId $disconnectPacketId `
        -PlayProtocolMode "vanilla" `
        -ExpectedUsername "EntityV1"
}
Invoke-Step "play-combat-lifecycle-vanilla-locked" {
    & (Join-Path $selfDir "e2e-play-combat-lifecycle.ps1") `
        -JavaBinary $JavaBinary `
        -DistPath $DistPath `
        -BackendPort ($BaseBackendPort + 80) `
        -Protocol $Protocol `
        -DisconnectPacketId $disconnectPacketId `
        -PlayProtocolMode "vanilla" `
        -ExpectedUsername "CombatV1"
}
Invoke-Step "play-anti-crash" {
    & (Join-Path $selfDir "e2e-play-anti-crash.ps1") `
        -JavaBinary $JavaBinary `
        -DistPath $DistPath `
        -BackendPort ($BaseBackendPort + 100) `
        -MalformedConnections 60
}
Invoke-Step "configure-benchmark-profile" {
    & (Join-Path $selfDir "configure-finished-v1.ps1") `
        -DistPath $DistPath `
        -ProtocolVersion $Protocol `
        -DisableLoginProtocolLock
}
Invoke-Step "play-benchmark-smoke" {
    & (Join-Path $selfDir "e2e-play-benchmark.ps1") `
        -JavaBinary $JavaBinary `
        -DistPath $DistPath `
        -Iterations 1 `
        -BaseBackendPort ($BaseBackendPort + 200) `
        -OnlyTests e2e-play-entity-inventory-modern-matrix.ps1
}

Write-Host "[ONYX] E2E_FINISHED_V1_OK"
Write-Host "[ONYX] PROTOCOL=$Protocol"
