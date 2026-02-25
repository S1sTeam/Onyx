param(
    [string]$JavaBinary = "java",
    [string]$DistPath = "dist",
    [int]$BaseBackendPort = 36610
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$runner = Join-Path $PSScriptRoot "e2e-play-keepalive-vanilla-modern.ps1"
if (-not (Test-Path $runner)) {
    throw "Missing keepalive modern runner: $runner"
}

$cases = @(
    [PSCustomObject]@{
        Protocol = 769
        DisconnectPacketId = 0x1D
        KeepAliveClientboundId = 0x27
        KeepAliveServerboundId = 0x1A
        Username = "KeepA769"
    },
    [PSCustomObject]@{
        Protocol = 770
        DisconnectPacketId = 0x1C
        KeepAliveClientboundId = 0x26
        KeepAliveServerboundId = 0x1A
        Username = "KeepA770"
    },
    [PSCustomObject]@{
        Protocol = 773
        DisconnectPacketId = 0x20
        KeepAliveClientboundId = 0x2B
        KeepAliveServerboundId = 0x1B
        Username = "KeepA773"
    },
    [PSCustomObject]@{
        Protocol = 774
        DisconnectPacketId = 0x20
        KeepAliveClientboundId = 0x2B
        KeepAliveServerboundId = 0x1B
        Username = "KeepA774"
    },
    [PSCustomObject]@{
        Protocol = 775
        DisconnectPacketId = 0x20
        KeepAliveClientboundId = 0x2B
        KeepAliveServerboundId = 0x1B
        Username = "KeepA775"
    }
)

$results = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $cases.Count; $i++) {
    $case = $cases[$i]
    $backendPort = $BaseBackendPort + $i
    Write-Host "[ONYX][KEEPALIVE-MATRIX] RUN protocol=$($case.Protocol) port=$backendPort"
    try {
        & $runner `
            -JavaBinary $JavaBinary `
            -DistPath $DistPath `
            -BackendPort $backendPort `
            -Protocol $case.Protocol `
            -DisconnectPacketId $case.DisconnectPacketId `
            -KeepAliveClientboundId $case.KeepAliveClientboundId `
            -KeepAliveServerboundId $case.KeepAliveServerboundId `
            -ExpectedUsername $case.Username `
            -UseAutoPacketIds
    } catch {
        throw "Matrix case failed for protocol=$($case.Protocol): $($_.Exception.Message)"
    }
    $results.Add("$($case.Protocol)=ok") | Out-Null
}

Write-Host "[ONYX] E2E_PLAY_KEEPALIVE_VANILLA_MODERN_MATRIX_OK"
Write-Host "[ONYX] MATRIX_RESULTS=$([string]::Join(',', $results))"
