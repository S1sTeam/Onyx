param(
    [string]$JavaBinary = "java",
    [string]$DistPath = "dist",
    [int]$BackendPort = 40766,
    [int]$Protocol = 769,
    [int]$DisconnectPacketId = 0x1D,
    [int]$LoginAckPacketId = 0x03,
    [int]$ConfigFinishPacketId = 0x03,
    [int]$EntityStatePacketId = 0x79,
    [int]$EntityActionPacketId = 0x7A,
    [int]$EntityUpdatePacketId = 0x7B,
    [int]$InventoryStatePacketId = 0x7C,
    [int]$InventoryActionPacketId = 0x7D,
    [int]$InventoryUpdatePacketId = 0x7E,
    [string]$PlayProtocolMode = "onyx",
    [string]$ExpectedUsername = "EntityInvProbe",
    [string]$ExpectedEntityType = "onyx:player",
    [int]$ExpectedInventorySize = 27,
    [int]$EntitySetHealthAction = 0,
    [int]$EntitySetHealthValue = 12,
    [int]$InventorySetAction = 0,
    [int]$InventorySetSlot = 3,
    [int]$InventorySetItemId = 5,
    [int]$InventorySetAmount = 16
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ExpectedUsername)) {
    throw "ExpectedUsername must not be empty."
}
if ($ExpectedUsername.Length -gt 16) {
    throw "ExpectedUsername exceeds 16 characters: $ExpectedUsername"
}
if ([string]::IsNullOrWhiteSpace($PlayProtocolMode)) {
    throw "PlayProtocolMode must not be empty."
}
function Write-VarInt([System.IO.Stream]$stream, [int]$value) {
    $v = [System.BitConverter]::ToUInt32([System.BitConverter]::GetBytes($value), 0)
    while ($true) {
    
    if (($v -band 0xFFFFFF80) -eq 0) {
    
    
    $stream.WriteByte([byte]$v)
    
    
    break
    
    }
    
    $stream.WriteByte([byte](($v -band 0x7F) -bor 0x80))
    
    $v = $v -shr 7
    }}
function Read-VarInt([System.IO.Stream]$stream) {
    $numRead = 0
    $result = 0
    while ($true) {
    
    $raw = $stream.ReadByte()
    
    if ($raw -lt 0) {
    
    
    throw "Unexpected EOF while reading VarInt"
    
    }
    
    $result = $result -bor (($raw -band 0x7F) -shl (7 * $numRead))
    
    $numRead++
    
    if ($numRead -gt 5) {
    
    
    throw "VarInt too big"
    
    }
    
    if (($raw -band 0x80) -eq 0) {
    
    
    break
    
    }
    }
    return $result}
function Read-Exact([System.IO.Stream]$stream, [int]$len) {
    $buffer = New-Object byte[] $len
    $offset = 0
    while ($offset -lt $len) {
    
    $read = $stream.Read($buffer, $offset, $len - $offset)
    
    if ($read -le 0) {
    
    
    throw "Unexpected EOF while reading bytes"
    
    }
    
    $offset += $read
    }
    return $buffer}
function Write-McString([System.IO.Stream]$stream, [string]$value) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($value)
    Write-VarInt $stream $bytes.Length
    $stream.Write($bytes, 0, $bytes.Length)}
function Read-McString([System.IO.Stream]$stream) {
    $len = Read-VarInt $stream
    $bytes = Read-Exact $stream $len
    return [System.Text.Encoding]::UTF8.GetString($bytes)}
function Write-UShortBE([System.IO.Stream]$stream, [int]$value) {
    $stream.WriteByte([byte](($value -shr 8) -band 0xFF))
    $stream.WriteByte([byte]($value -band 0xFF))}
function Read-UShortBE([System.IO.Stream]$stream) {
    $hi = $stream.ReadByte()
    $lo = $stream.ReadByte()
    if ($hi -lt 0 -or $lo -lt 0) {
    
    throw "Unexpected EOF while reading unsigned short"
    }
    return (($hi -shl 8) -bor $lo)}
function Build-Packet([ScriptBlock]$writer) {
    $body = New-Object System.IO.MemoryStream
    & $writer $body
    $bodyBytes = $body.ToArray()
    $packet = New-Object System.IO.MemoryStream
    Write-VarInt $packet $bodyBytes.Length
    $packet.Write($bodyBytes, 0, $bodyBytes.Length)
    return $packet.ToArray()}
function Read-Packet([System.IO.Stream]$stream) {
    $packetLen = Read-VarInt $stream
    $packetBody = Read-Exact $stream $packetLen
    $packetMem = New-Object System.IO.MemoryStream(, $packetBody)
    $packetId = Read-VarInt $packetMem
    return [PSCustomObject]@{
    
    Id = $packetId
    
    Stream = $packetMem
    }}
function Read-NbtString([System.IO.Stream]$stream) {
    $len = Read-UShortBE $stream
    $bytes = Read-Exact $stream $len
    return [System.Text.Encoding]::UTF8.GetString($bytes)}
function Read-AnonymousNbtText([System.IO.Stream]$stream) {
    $tagType = $stream.ReadByte()
    if ($tagType -ne 0x0A) {
    
    throw "Expected TAG_Compound, got $tagType"
    }
    $text = $null
    while ($true) {
    
    $entryType = $stream.ReadByte()
    
    if ($entryType -lt 0) {
    
    
    throw "Unexpected EOF while reading NBT entry"
    
    }
    
    if ($entryType -eq 0x00) {
    
    
    break
    
    }
    
    $name = Read-NbtString $stream
    
    if ($entryType -eq 0x08) {
    
    
    $value = Read-NbtString $stream
    
    
    if ($name -eq "text") {
    
    
    
    $text = $value
    
    
    }
    
    } else {
    
    
    throw "Unsupported NBT type in parser: $entryType"
    
    }
    }
    return $text}
function Convert-GuidToNetworkBytes([Guid]$guid) {
    $guidBytes = $guid.ToByteArray()
    $out = New-Object byte[] 16
    $out[0] = $guidBytes[3]
    $out[1] = $guidBytes[2]
    $out[2] = $guidBytes[1]
    $out[3] = $guidBytes[0]
    $out[4] = $guidBytes[5]
    $out[5] = $guidBytes[4]
    $out[6] = $guidBytes[7]
    $out[7] = $guidBytes[6]
    for ($i = 8; $i -lt 16; $i++) {
    
    $out[$i] = $guidBytes[$i]
    }
    return $out}
function New-JavaProcess([string]$fileName, [string]$workingDir, [string]$arguments) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $fileName
    $psi.WorkingDirectory = $workingDir
    $psi.Arguments = $arguments
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()
    return $proc}
function Stop-JavaProcess($proc, [string]$stopCommand) {
    if ($null -eq $proc) {
    
    return
    }
    if ($proc.HasExited) {
    
    return
    }
    try {
    
    $proc.StandardInput.WriteLine($stopCommand)
    
    $proc.StandardInput.Flush()
    } catch {
    }
    if (-not $proc.WaitForExit(5000)) {
    
    $proc.Kill()
    }}
function Wait-TcpPort([string]$hostName, [int]$port, [int]$timeoutMs) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $timeoutMs) {
    
    $client = New-Object System.Net.Sockets.TcpClient
    
    try {
    
    
    $async = $client.BeginConnect($hostName, $port, $null, $null)
    
    
    if ($async.AsyncWaitHandle.WaitOne(200) -and $client.Connected) {
    
    
    
    $client.EndConnect($async)
    
    
    
    return
    
    
    }
    
    } catch {
    
    } finally {
    
    
    $client.Close()
    
    }
    
    Start-Sleep -Milliseconds 100
    }
    throw "Timeout waiting for ${hostName}:${port}"}
function Upsert-Line([string]$content, [string]$pattern, [string]$line) {
    if ($content -match $pattern) {
    
    return [System.Text.RegularExpressions.Regex]::Replace($content, $pattern, $line)
    }
    if ($content.Length -gt 0 -and -not $content.EndsWith("`n")) {
    
    $content += "`n"
    }
    return $content + $line}
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$dist = Join-Path $root $DistPath
$serverDir = Join-Path $dist "runtime/onyxserver"
$serverJar = Join-Path $serverDir "onyxserver.jar"
$serverConfigPath = Join-Path $serverDir "onyxserver.conf"
if (-not (Test-Path $serverJar)) {
    throw "Missing $serverJar. Run scripts/build-onyx.ps1 first."
}
if (-not (Test-Path $serverConfigPath)) {
    throw "Missing $serverConfigPath. Run scripts/run-onyx.ps1 -InitOnly first."}
$server = $null
$client = $null
$originalServerConfig = $null
try {
    $originalServerConfig = Get-Content -Raw -Encoding UTF8 $serverConfigPath
    $serverConfig = $originalServerConfig
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^bind\s*=.*$' -line "bind = 127.0.0.1:$BackendPort"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^forwarding-mode\s*=.*$' -line "forwarding-mode = disabled"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-protocol-mode\s*=.*$' -line "play-protocol-mode = $PlayProtocolMode"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-enabled\s*=.*$' -line "play-session-enabled = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-duration-ms\s*=.*$' -line "play-session-duration-ms = 1200"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-poll-timeout-ms\s*=.*$' -line "play-session-poll-timeout-ms = 40"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-max-packets\s*=.*$' -line "play-session-max-packets = 256"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-disconnect-on-limit\s*=.*$' -line "play-session-disconnect-on-limit = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-persistent\s*=.*$' -line "play-session-persistent = false"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-keepalive-enabled\s*=.*$' -line "play-keepalive-enabled = false"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-keepalive-clientbound-packet-id\s*=.*$' -line "play-keepalive-clientbound-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-keepalive-serverbound-packet-id\s*=.*$' -line "play-keepalive-serverbound-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-keepalive-require-ack\s*=.*$' -line "play-keepalive-require-ack = false"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-keepalive-ack-timeout-ms\s*=.*$' -line "play-keepalive-ack-timeout-ms = 300"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-enabled\s*=.*$' -line "play-bootstrap-enabled = false"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-movement-enabled\s*=.*$' -line "play-movement-enabled = false"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-input-enabled\s*=.*$' -line "play-input-enabled = false"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-world-enabled\s*=.*$' -line "play-world-enabled = false"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-entity-enabled\s*=.*$' -line "play-entity-enabled = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-entity-state-packet-id\s*=.*$' -line "play-entity-state-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-entity-action-packet-id\s*=.*$' -line "play-entity-action-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-entity-update-packet-id\s*=.*$' -line "play-entity-update-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-inventory-enabled\s*=.*$' -line "play-inventory-enabled = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-inventory-state-packet-id\s*=.*$' -line "play-inventory-state-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-inventory-action-packet-id\s*=.*$' -line "play-inventory-action-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-inventory-update-packet-id\s*=.*$' -line "play-inventory-update-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-inventory-size\s*=.*$' -line "play-inventory-size = $ExpectedInventorySize"
    Set-Content -Path $serverConfigPath -Value $serverConfig -Encoding UTF8 -NoNewline
    $server = New-JavaProcess -fileName $JavaBinary -workingDir $serverDir -arguments "-jar onyxserver.jar --config onyxserver.conf --onyx-settings onyx.yml"
    Start-Sleep -Milliseconds 1200
    if ($server.HasExited) {
    
    throw "OnyxServer exited early. stderr: $($server.StandardError.ReadToEnd())"
    }
    Wait-TcpPort -hostName "127.0.0.1" -port $BackendPort -timeoutMs 8000
    $client = New-Object System.Net.Sockets.TcpClient
    $client.Connect("127.0.0.1", $BackendPort)
    $stream = $client.GetStream()
    $stream.ReadTimeout = 8000
    $uuidBytes = Convert-GuidToNetworkBytes -guid ([Guid]::NewGuid())
    $handshake = Build-Packet {
    
    param($packetBody)
    
    Write-VarInt $packetBody 0x00
    
    Write-VarInt $packetBody $Protocol
    
    Write-McString $packetBody "127.0.0.1"
    
    Write-UShortBE $packetBody $BackendPort
    
    Write-VarInt $packetBody 0x02
    }
    $loginStart = Build-Packet {
    
    param($packetBody)
    
    Write-VarInt $packetBody 0x00
    
    Write-McString $packetBody $ExpectedUsername
    
    $packetBody.Write($uuidBytes, 0, $uuidBytes.Length)
    }
    $stream.Write($handshake, 0, $handshake.Length)
    $stream.Write($loginStart, 0, $loginStart.Length)
    $loginSuccess = Read-Packet $stream
    if ($loginSuccess.Id -ne 0x02) {
    
    throw "Expected login success packet (0x02), got $($loginSuccess.Id)"
    }
    [void](Read-Exact $loginSuccess.Stream 16)
    [void](Read-McString $loginSuccess.Stream)
    [void](Read-VarInt $loginSuccess.Stream)
    $loginAck = Build-Packet {
    
    param($packetBody)
    
    Write-VarInt $packetBody $LoginAckPacketId
    }
    $stream.Write($loginAck, 0, $loginAck.Length)
    $configFinish = Read-Packet $stream
    if ($configFinish.Id -ne $ConfigFinishPacketId) {
    
    throw "Expected config finish packet ($ConfigFinishPacketId), got $($configFinish.Id)"
    }
    $clientFinish = Build-Packet {
    
    param($packetBody)
    
    Write-VarInt $packetBody $ConfigFinishPacketId
    }
    $stream.Write($clientFinish, 0, $clientFinish.Length)
    $seenEntityState = $false
    $seenInventoryState = $false
    $entityId = -1
    $swInit = [System.Diagnostics.Stopwatch]::StartNew()
    while (($swInit.ElapsedMilliseconds -lt 5000) -and (-not ($seenEntityState -and $seenInventoryState))) {
    
    $packet = Read-Packet $stream
    
    if ($packet.Id -eq $EntityStatePacketId) {
    
    
    $entityId = Read-VarInt $packet.Stream
    
    
    $entityType = Read-McString $packet.Stream
    
    
    $entityUser = Read-McString $packet.Stream
    
    
    $entityHealth = Read-VarInt $packet.Stream
    
    
    $entityHunger = Read-VarInt $packet.Stream
    
    
    $entityAliveRaw = $packet.Stream.ReadByte()
    
    
    if ($entityType -ne $ExpectedEntityType) {
    
    
    
    throw "Entity type mismatch: expected '$ExpectedEntityType', got '$entityType'"
    
    
    }
    
    
    if ($entityUser -ne $ExpectedUsername) {
    
    
    
    throw "Entity username mismatch: expected '$ExpectedUsername', got '$entityUser'"
    
    
    }
    
    
    if ($entityHealth -ne 20 -or $entityHunger -ne 20) {
    
    
    
    throw "Unexpected initial entity state health/hunger: $entityHealth/$entityHunger"
    
    
    }
    
    
    if ($entityAliveRaw -ne 1) {
    
    
    
    throw "Expected entity alive flag 1, got $entityAliveRaw"
    
    
    }
    
    
    $seenEntityState = $true
    
    
    continue
    
    }
    
    if ($packet.Id -eq $InventoryStatePacketId) {
    
    
    $invSize = Read-VarInt $packet.Stream
    
    
    if ($invSize -ne $ExpectedInventorySize) {
    
    
    
    throw "Inventory size mismatch: expected $ExpectedInventorySize, got $invSize"
    
    
    }
    
    
    $itemCount = Read-VarInt $packet.Stream
    
    
    for ($i = 0; $i -lt $itemCount; $i++) {
    
    
    
    [void](Read-VarInt $packet.Stream)
    
    
    
    [void](Read-VarInt $packet.Stream)
    
    
    
    [void](Read-VarInt $packet.Stream)
    
    
    }
    
    
    $seenInventoryState = $true
    
    
    continue
    
    }
    
    if ($packet.Id -eq $DisconnectPacketId) {
    
    
    $disconnectText = Read-AnonymousNbtText $packet.Stream
    
    
    throw "Received disconnect before entity/inventory state: $disconnectText"
    
    }
    }
    if (-not $seenEntityState) {
    
    throw "Did not receive entity state packet"
    }
    if (-not $seenInventoryState) {
    
    throw "Did not receive inventory state packet"
    }
    if ($entityId -lt 0) {
    
    throw "Entity id was not initialized"
    }
    $entityAction = Build-Packet {
    
    param($packetBody)
    
    Write-VarInt $packetBody $EntityActionPacketId
    
    Write-VarInt $packetBody $EntitySetHealthAction
    
    Write-VarInt $packetBody $entityId
    
    Write-VarInt $packetBody $EntitySetHealthValue
    }
    $stream.Write($entityAction, 0, $entityAction.Length)
    $inventoryAction = Build-Packet {
    
    param($packetBody)
    
    Write-VarInt $packetBody $InventoryActionPacketId
    
    Write-VarInt $packetBody $InventorySetAction
    
    Write-VarInt $packetBody $InventorySetSlot
    
    Write-VarInt $packetBody $InventorySetItemId
    
    Write-VarInt $packetBody $InventorySetAmount
    }
    $stream.Write($inventoryAction, 0, $inventoryAction.Length)
    $seenEntityUpdate = $false
    $seenInventoryUpdate = $false
    $disconnectReason = ""
    $swTail = [System.Diagnostics.Stopwatch]::StartNew()
    while ($swTail.ElapsedMilliseconds -lt 8000) {
    
    $packet = Read-Packet $stream
    
    if ($packet.Id -eq $EntityUpdatePacketId) {
    
    
    $resultCode = Read-VarInt $packet.Stream
    
    
    $actionType = Read-VarInt $packet.Stream
    
    
    $updatedEntityId = Read-VarInt $packet.Stream
    
    
    $health = Read-VarInt $packet.Stream
    
    
    [void](Read-VarInt $packet.Stream) # hunger
    
    
    [void]$packet.Stream.ReadByte() # alive
    
    
    $changedRaw = $packet.Stream.ReadByte()
    
    
    if ($resultCode -ne 0) {
    
    
    
    throw "Entity update result is not success: $resultCode"
    
    
    }
    
    
    if ($actionType -ne $EntitySetHealthAction) {
    
    
    
    throw "Entity action mismatch: expected $EntitySetHealthAction, got $actionType"
    
    
    }
    
    
    if ($updatedEntityId -ne $entityId) {
    
    
    
    throw "Entity id mismatch in update: expected $entityId, got $updatedEntityId"
    
    
    }
    
    
    if ($health -ne $EntitySetHealthValue) {
    
    
    
    throw "Entity health mismatch in update: expected $EntitySetHealthValue, got $health"
    
    
    }
    
    
    if ($changedRaw -ne 1) {
    
    
    
    throw "Expected entity changed=1, got $changedRaw"
    
    
    }
    
    
    $seenEntityUpdate = $true
    
    
    continue
    
    }
    
    if ($packet.Id -eq $InventoryUpdatePacketId) {
    
    
    $resultCode = Read-VarInt $packet.Stream
    
    
    $actionType = Read-VarInt $packet.Stream
    
    
    $slot = Read-VarInt $packet.Stream
    
    
    $itemId = Read-VarInt $packet.Stream
    
    
    $amount = Read-VarInt $packet.Stream
    
    
    $changedRaw = $packet.Stream.ReadByte()
    
    
    if ($resultCode -ne 0) {
    
    
    
    throw "Inventory update result is not success: $resultCode"
    
    
    }
    
    
    if ($actionType -ne $InventorySetAction) {
    
    
    
    throw "Inventory action mismatch: expected $InventorySetAction, got $actionType"
    
    
    }
    
    
    if ($slot -ne $InventorySetSlot -or $itemId -ne $InventorySetItemId -or $amount -ne $InventorySetAmount) {
    
    
    
    throw "Inventory update mismatch"
    
    
    }
    
    
    if ($changedRaw -ne 1) {
    
    
    
    throw "Expected inventory changed=1, got $changedRaw"
    
    
    }
    
    
    $seenInventoryUpdate = $true
    
    
    continue
    
    }
    
    if ($packet.Id -eq $DisconnectPacketId) {
    
    
    $disconnectReason = Read-AnonymousNbtText $packet.Stream
    
    
    break
    
    }
    }
    if (-not $seenEntityUpdate) {
    
    throw "Did not receive entity update packet"
    }
    if (-not $seenInventoryUpdate) {
    
    throw "Did not receive inventory update packet"
    }
    if ([string]::IsNullOrWhiteSpace($disconnectReason)) {
    
    throw "Did not receive play disconnect packet"
    }
    if (-not $disconnectReason.Contains("entity-actions=1")) {
    
    throw "Disconnect reason missing entity-actions=1: $disconnectReason"
    }
    if (-not $disconnectReason.Contains("inventory-actions=1")) {
    
    throw "Disconnect reason missing inventory-actions=1: $disconnectReason"
    }
    Write-Host "E2E_PLAY_ENTITY_INVENTORY_OK"
} finally {
    if ($null -ne $client) {
    
    try {
    
    
    $client.Close()
    
    } catch {
    
    }
    }
    Stop-JavaProcess -proc $server -stopCommand "stop"
    if ($null -ne $originalServerConfig) {
    
    Set-Content -Path $serverConfigPath -Value $originalServerConfig -Encoding UTF8 -NoNewline
    }}
