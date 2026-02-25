param(
    [string]$JavaBinary = "java",
    [string]$DistPath = "dist",
    [int]$BaseBackendPort = 48410
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$worldRunner = Join-Path $PSScriptRoot "e2e-play-world.ps1"
$entityRunner = Join-Path $PSScriptRoot "e2e-play-entity-inventory.ps1"
$combatRunner = Join-Path $PSScriptRoot "e2e-play-combat.ps1"
if (-not (Test-Path $worldRunner)) {
    throw "Missing world runner: $worldRunner"
}
if (-not (Test-Path $entityRunner)) {
    throw "Missing entity runner: $entityRunner"
}
if (-not (Test-Path $combatRunner)) {
    throw "Missing combat runner: $combatRunner"
}

$cases = @(
    [PSCustomObject]@{ Protocol = 770; DisconnectPacketId = 0x1C },
    [PSCustomObject]@{ Protocol = 773; DisconnectPacketId = 0x20 },
    [PSCustomObject]@{ Protocol = 774; DisconnectPacketId = 0x20 },
    [PSCustomObject]@{ Protocol = 775; DisconnectPacketId = 0x20 }
)

$results = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $cases.Count; $i++) {
    $case = $cases[$i]
    $basePort = $BaseBackendPort + ($i * 3)

    Write-Host "[ONYX][EXT-VANILLA] RUN-WORLD protocol=$($case.Protocol) port=$basePort"
    & $worldRunner `
        -JavaBinary $JavaBinary `
        -DistPath $DistPath `
        -BackendPort $basePort `
        -Protocol $case.Protocol `
        -DisconnectPacketId $case.DisconnectPacketId `
        -PlayProtocolMode "vanilla" `
        -ExpectedUsername ("WExt" + $case.Protocol)

    Write-Host "[ONYX][EXT-VANILLA] RUN-ENTITY protocol=$($case.Protocol) port=$($basePort + 1)"
    & $entityRunner `
        -JavaBinary $JavaBinary `
        -DistPath $DistPath `
        -BackendPort ($basePort + 1) `
        -Protocol $case.Protocol `
        -DisconnectPacketId $case.DisconnectPacketId `
        -PlayProtocolMode "vanilla" `
        -ExpectedUsername ("EExt" + $case.Protocol)

    Write-Host "[ONYX][EXT-VANILLA] RUN-COMBAT protocol=$($case.Protocol) port=$($basePort + 2)"
    & $combatRunner `
        -JavaBinary $JavaBinary `
        -DistPath $DistPath `
        -BackendPort ($basePort + 2) `
        -Protocol $case.Protocol `
        -DisconnectPacketId $case.DisconnectPacketId `
        -PlayProtocolMode "vanilla" `
        -ExpectedUsername ("CExt" + $case.Protocol)

    $results.Add("$($case.Protocol)=ok") | Out-Null
}

Write-Host "[ONYX] E2E_PLAY_EXTENSIONS_VANILLA_MODERN_MATRIX_OK"
Write-Host "[ONYX] MATRIX_RESULTS=$([string]::Join(',', $results))"
