param(
    [string]$JavaBinary = "java",
    [string]$DistPath = "dist",
    [int]$BaseBackendPort = 36810
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$positionRunner = Join-Path $PSScriptRoot "e2e-play-movement-vanilla-flags.ps1"
$rotationRunner = Join-Path $PSScriptRoot "e2e-play-movement-rotation-vanilla-flags.ps1"
if (-not (Test-Path $positionRunner)) {
    throw "Missing movement vanilla flags runner: $positionRunner"
}
if (-not (Test-Path $rotationRunner)) {
    throw "Missing movement rotation vanilla flags runner: $rotationRunner"
}

$cases = @(
    [PSCustomObject]@{
        Protocol = 769
        DisconnectPacketId = 0x1D
        BootstrapInitPacketId = 0x2C
        BootstrapSpawnPacketId = 0x42
        BootstrapMessagePacketId = 0x73
        PositionPacketId = 0x1C
        RotationPacketId = 0x1E
        PositionRotationPacketId = 0x1D
        OnGroundPacketId = 0x1F
    },
    [PSCustomObject]@{
        Protocol = 770
        DisconnectPacketId = 0x1C
        BootstrapInitPacketId = 0x2B
        BootstrapSpawnPacketId = 0x41
        BootstrapMessagePacketId = 0x72
        PositionPacketId = 0x1C
        RotationPacketId = 0x1E
        PositionRotationPacketId = 0x1D
        OnGroundPacketId = 0x1F
    },
    [PSCustomObject]@{
        Protocol = 773
        DisconnectPacketId = 0x20
        BootstrapInitPacketId = 0x30
        BootstrapSpawnPacketId = 0x46
        BootstrapMessagePacketId = 0x77
        PositionPacketId = 0x1D
        RotationPacketId = 0x1F
        PositionRotationPacketId = 0x1E
        OnGroundPacketId = 0x20
    },
    [PSCustomObject]@{
        Protocol = 774
        DisconnectPacketId = 0x20
        BootstrapInitPacketId = 0x30
        BootstrapSpawnPacketId = 0x46
        BootstrapMessagePacketId = 0x77
        PositionPacketId = 0x1D
        RotationPacketId = 0x1F
        PositionRotationPacketId = 0x1E
        OnGroundPacketId = 0x20
    },
    [PSCustomObject]@{
        Protocol = 775
        DisconnectPacketId = 0x20
        BootstrapInitPacketId = 0x30
        BootstrapSpawnPacketId = 0x46
        BootstrapMessagePacketId = 0x77
        PositionPacketId = 0x1D
        RotationPacketId = 0x1F
        PositionRotationPacketId = 0x1E
        OnGroundPacketId = 0x20
    }
)

$results = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $cases.Count; $i++) {
    $case = $cases[$i]
    $backendPortPosition = $BaseBackendPort + ($i * 2)
    $backendPortRotation = $backendPortPosition + 1

    Write-Host "[ONYX][MOVE-MATRIX] RUN-POS protocol=$($case.Protocol) port=$backendPortPosition"
    try {
        & $positionRunner `
            -JavaBinary $JavaBinary `
            -DistPath $DistPath `
            -BackendPort $backendPortPosition `
            -Protocol $case.Protocol `
            -DisconnectPacketId $case.DisconnectPacketId `
            -BootstrapInitPacketId $case.BootstrapInitPacketId `
            -BootstrapSpawnPacketId $case.BootstrapSpawnPacketId `
            -BootstrapMessagePacketId $case.BootstrapMessagePacketId `
            -PositionPacketId $case.PositionPacketId `
            -OnGroundPacketId $case.OnGroundPacketId `
            -ExpectedUsername ("MoveP" + $case.Protocol)
    } catch {
        throw "Movement matrix position case failed for protocol=$($case.Protocol): $($_.Exception.Message)"
    }

    Write-Host "[ONYX][MOVE-MATRIX] RUN-ROT protocol=$($case.Protocol) port=$backendPortRotation"
    try {
        & $rotationRunner `
            -JavaBinary $JavaBinary `
            -DistPath $DistPath `
            -BackendPort $backendPortRotation `
            -Protocol $case.Protocol `
            -DisconnectPacketId $case.DisconnectPacketId `
            -BootstrapInitPacketId $case.BootstrapInitPacketId `
            -BootstrapSpawnPacketId $case.BootstrapSpawnPacketId `
            -BootstrapMessagePacketId $case.BootstrapMessagePacketId `
            -RotationPacketId $case.RotationPacketId `
            -PositionRotationPacketId $case.PositionRotationPacketId `
            -ExpectedUsername ("MoveR" + $case.Protocol)
    } catch {
        throw "Movement matrix rotation case failed for protocol=$($case.Protocol): $($_.Exception.Message)"
    }

    $results.Add("$($case.Protocol)=ok") | Out-Null
}

Write-Host "[ONYX] E2E_PLAY_MOVEMENT_VANILLA_MODERN_MATRIX_OK"
Write-Host "[ONYX] MATRIX_RESULTS=$([string]::Join(',', $results))"
