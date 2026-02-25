param(
    [string]$JavaBinary = "java",
    [string]$DistPath = "dist",
    [int]$BaseBackendPort = 36710
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$runner = Join-Path $PSScriptRoot "e2e-play-bootstrap-protocol-vanilla.ps1"
if (-not (Test-Path $runner)) {
    throw "Missing vanilla bootstrap protocol runner: $runner"
}

$cases = @(
    [PSCustomObject]@{
        Protocol = 769
        DisconnectPacketId = 0x1D
        BootstrapInitPacketId = 0x2C
        BootstrapSpawnPacketId = 0x42
        BootstrapMessagePacketId = 0x73
        Username = "BootP769"
    },
    [PSCustomObject]@{
        Protocol = 770
        DisconnectPacketId = 0x1C
        BootstrapInitPacketId = 0x2B
        BootstrapSpawnPacketId = 0x41
        BootstrapMessagePacketId = 0x72
        Username = "BootP770"
    },
    [PSCustomObject]@{
        Protocol = 773
        DisconnectPacketId = 0x20
        BootstrapInitPacketId = 0x30
        BootstrapSpawnPacketId = 0x46
        BootstrapMessagePacketId = 0x77
        Username = "BootP773"
    },
    [PSCustomObject]@{
        Protocol = 774
        DisconnectPacketId = 0x20
        BootstrapInitPacketId = 0x30
        BootstrapSpawnPacketId = 0x46
        BootstrapMessagePacketId = 0x77
        Username = "BootP774"
    },
    [PSCustomObject]@{
        Protocol = 775
        DisconnectPacketId = 0x20
        BootstrapInitPacketId = 0x30
        BootstrapSpawnPacketId = 0x46
        BootstrapMessagePacketId = 0x77
        Username = "BootP775"
    }
)

$results = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $cases.Count; $i++) {
    $case = $cases[$i]
    $backendPort = $BaseBackendPort + $i
    Write-Host "[ONYX][BOOTSTRAP-MATRIX] RUN protocol=$($case.Protocol) port=$backendPort"
    try {
        & $runner `
            -JavaBinary $JavaBinary `
            -DistPath $DistPath `
            -BackendPort $backendPort `
            -Protocol $case.Protocol `
            -DisconnectPacketId $case.DisconnectPacketId `
            -BootstrapInitPacketId $case.BootstrapInitPacketId `
            -BootstrapSpawnPacketId $case.BootstrapSpawnPacketId `
            -BootstrapMessagePacketId $case.BootstrapMessagePacketId `
            -ExpectedUsername $case.Username
    } catch {
        throw "Matrix case failed for protocol=$($case.Protocol): $($_.Exception.Message)"
    }
    $results.Add("$($case.Protocol)=ok") | Out-Null
}

Write-Host "[ONYX] E2E_PLAY_BOOTSTRAP_PROTOCOL_VANILLA_MODERN_MATRIX_OK"
Write-Host "[ONYX] MATRIX_RESULTS=$([string]::Join(',', $results))"
