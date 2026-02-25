param(
    [string]$JavaBinary = "java",
    [string]$DistPath = "dist",
    [int]$BaseBackendPort = 36910
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$runner = Join-Path $PSScriptRoot "e2e-play-input-response-vanilla.ps1"
if (-not (Test-Path $runner)) {
    throw "Missing input response vanilla runner: $runner"
}

$cases = @(
    [PSCustomObject]@{
        Protocol = 769
        DisconnectPacketId = 0x1D
        ChatPacketId = 0x07
        CommandPacketId = 0x05
        ResponsePacketId = 0x73
        Username = "InResp769"
    },
    [PSCustomObject]@{
        Protocol = 770
        DisconnectPacketId = 0x1C
        ChatPacketId = 0x07
        CommandPacketId = 0x05
        ResponsePacketId = 0x72
        Username = "InResp770"
    },
    [PSCustomObject]@{
        Protocol = 773
        DisconnectPacketId = 0x20
        ChatPacketId = 0x08
        CommandPacketId = 0x06
        ResponsePacketId = 0x77
        Username = "InResp773"
    },
    [PSCustomObject]@{
        Protocol = 774
        DisconnectPacketId = 0x20
        ChatPacketId = 0x08
        CommandPacketId = 0x06
        ResponsePacketId = 0x77
        Username = "InResp774"
    },
    [PSCustomObject]@{
        Protocol = 775
        DisconnectPacketId = 0x20
        ChatPacketId = 0x08
        CommandPacketId = 0x06
        ResponsePacketId = 0x77
        Username = "InResp775"
    }
)

$results = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $cases.Count; $i++) {
    $case = $cases[$i]
    $backendPort = $BaseBackendPort + $i
    Write-Host "[ONYX][INPUT-MATRIX] RUN protocol=$($case.Protocol) port=$backendPort"
    try {
        & $runner `
            -JavaBinary $JavaBinary `
            -DistPath $DistPath `
            -BackendPort $backendPort `
            -Protocol $case.Protocol `
            -DisconnectPacketId $case.DisconnectPacketId `
            -ChatPacketId $case.ChatPacketId `
            -CommandPacketId $case.CommandPacketId `
            -ResponsePacketId $case.ResponsePacketId `
            -ExpectedUsername $case.Username
    } catch {
        throw "Input-response matrix case failed for protocol=$($case.Protocol): $($_.Exception.Message)"
    }
    $results.Add("$($case.Protocol)=ok") | Out-Null
}

Write-Host "[ONYX] E2E_PLAY_INPUT_RESPONSE_VANILLA_MODERN_MATRIX_OK"
Write-Host "[ONYX] MATRIX_RESULTS=$([string]::Join(',', $results))"
