param(
    [string]$JavaBinary = "java",
    [string]$DistPath = "dist",
    [int]$BaseBackendPort = 37210
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$runner = Join-Path $PSScriptRoot "e2e-play-combat.ps1"
if (-not (Test-Path $runner)) {
    throw "Missing combat runner: $runner"
}

$cases = @(
    [PSCustomObject]@{
        Protocol = 769
        DisconnectPacketId = 0x1D
        Username = "Combat769"
    },
    [PSCustomObject]@{
        Protocol = 770
        DisconnectPacketId = 0x1C
        Username = "Combat770"
    },
    [PSCustomObject]@{
        Protocol = 773
        DisconnectPacketId = 0x20
        Username = "Combat773"
    },
    [PSCustomObject]@{
        Protocol = 774
        DisconnectPacketId = 0x20
        Username = "Combat774"
    },
    [PSCustomObject]@{
        Protocol = 775
        DisconnectPacketId = 0x20
        Username = "Combat775"
    }
)

$results = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $cases.Count; $i++) {
    $case = $cases[$i]
    $backendPort = $BaseBackendPort + $i
    Write-Host "[ONYX][COMBAT-MATRIX] RUN protocol=$($case.Protocol) port=$backendPort"
    try {
        & $runner `
            -JavaBinary $JavaBinary `
            -DistPath $DistPath `
            -BackendPort $backendPort `
            -Protocol $case.Protocol `
            -DisconnectPacketId $case.DisconnectPacketId `
            -ExpectedUsername $case.Username
    } catch {
        throw "Combat matrix case failed for protocol=$($case.Protocol): $($_.Exception.Message)"
    }
    $results.Add("$($case.Protocol)=ok") | Out-Null
}

Write-Host "[ONYX] E2E_PLAY_COMBAT_MODERN_MATRIX_OK"
Write-Host "[ONYX] MATRIX_RESULTS=$([string]::Join(',', $results))"
