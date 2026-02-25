param(
    [string]$JavaBinary = "java",
    [string]$DistPath = "dist",
    [int]$BackendPort = 40966,
    [int]$Protocol = 769,
    [int]$DisconnectPacketId = 0x1D,
    [int]$LoginAckPacketId = 0x03,
    [int]$ConfigFinishPacketId = 0x03,
    [int]$WorldStatePacketId = 0x75,
    [int]$WorldChunkPacketId = 0x76,
    [int]$EntityStatePacketId = 0x79,
    [int]$InteractActionPacketId = 0x7F,
    [int]$InteractUpdatePacketId = 0x80,
    [int]$CombatActionPacketId = 0x81,
    [int]$CombatUpdatePacketId = 0x82,
    [string]$PlayProtocolMode = "onyx",
    [string]$ExpectedUsername = "CombatLifeProbe",
    [string]$ExpectedEntityType = "onyx:player",
    [string]$ExpectedWorldName = "onyx:world",
    [int]$InteractActionPlace = 2,
    [int]$InteractX = 8,
    [int]$InteractY = 66,
    [int]$InteractZ = 8,
    [int]$InteractBlockId = 4,
    [int]$CombatActionAttack = 0,
    [int]$CombatActionHeal = 1,
    [int]$CombatActionRespawn = 3,
    [int]$CombatActionQuery = 2,
    [int]$CombatTargetEntityId = 2,
    [int]$CombatCooldownMs = 300,
    [int]$CombatRespawnDelayMs = 700,
    [int]$CombatAggroWindowMs = 1300,
    [int]$CombatDamageTypeMelee = 0,
    [int]$CombatDamageTypeProjectile = 1,
    [int]$CombatDamageTypeMagic = 2,
    [int]$CombatDamageTypeTrue = 3
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
function Read-Double([System.IO.Stream]$stream) {
    $bytes = Read-Exact $stream 8
    if ([System.BitConverter]::IsLittleEndian) {
    
    [Array]::Reverse($bytes)
    }
    return [System.BitConverter]::ToDouble($bytes, 0)}
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
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-duration-ms\s*=.*$' -line "play-session-duration-ms = 5200"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-poll-timeout-ms\s*=.*$' -line "play-session-poll-timeout-ms = 40"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-max-packets\s*=.*$' -line "play-session-max-packets = 300"
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
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-world-enabled\s*=.*$' -line "play-world-enabled = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-world-state-packet-id\s*=.*$' -line "play-world-state-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-world-chunk-packet-id\s*=.*$' -line "play-world-chunk-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-world-action-packet-id\s*=.*$' -line "play-world-action-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-world-block-update-packet-id\s*=.*$' -line "play-world-block-update-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-entity-enabled\s*=.*$' -line "play-entity-enabled = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-entity-state-packet-id\s*=.*$' -line "play-entity-state-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-entity-action-packet-id\s*=.*$' -line "play-entity-action-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-entity-update-packet-id\s*=.*$' -line "play-entity-update-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-interact-enabled\s*=.*$' -line "play-interact-enabled = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-interact-action-packet-id\s*=.*$' -line "play-interact-action-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-interact-update-packet-id\s*=.*$' -line "play-interact-update-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-combat-enabled\s*=.*$' -line "play-combat-enabled = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-combat-action-packet-id\s*=.*$' -line "play-combat-action-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-combat-update-packet-id\s*=.*$' -line "play-combat-update-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-combat-target-entity-id\s*=.*$' -line "play-combat-target-entity-id = $CombatTargetEntityId"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-combat-target-health\s*=.*$' -line "play-combat-target-health = 20"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-combat-target-x\s*=.*$' -line "play-combat-target-x = 2.0"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-combat-target-y\s*=.*$' -line "play-combat-target-y = 64.0"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-combat-target-z\s*=.*$' -line "play-combat-target-z = 2.0"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-combat-hit-range\s*=.*$' -line "play-combat-hit-range = 5.0"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-combat-attack-cooldown-ms\s*=.*$' -line "play-combat-attack-cooldown-ms = $CombatCooldownMs"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-combat-crit-enabled\s*=.*$' -line "play-combat-crit-enabled = false"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-combat-crit-multiplier\s*=.*$' -line "play-combat-crit-multiplier = 1.5"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-combat-allow-self-target\s*=.*$' -line "play-combat-allow-self-target = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-combat-target-respawn-delay-ms\s*=.*$' -line "play-combat-target-respawn-delay-ms = $CombatRespawnDelayMs"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-combat-target-aggro-window-ms\s*=.*$' -line "play-combat-target-aggro-window-ms = $CombatAggroWindowMs"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-combat-damage-multiplier-melee\s*=.*$' -line "play-combat-damage-multiplier-melee = 1.0"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-combat-damage-multiplier-projectile\s*=.*$' -line "play-combat-damage-multiplier-projectile = 2.0"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-combat-damage-multiplier-magic\s*=.*$' -line "play-combat-damage-multiplier-magic = 1.0"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-combat-damage-multiplier-true\s*=.*$' -line "play-combat-damage-multiplier-true = 1.0"
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
    $seenWorldState = $false
    $seenWorldChunk = $false
    $entityId = -1
    $swInit = [System.Diagnostics.Stopwatch]::StartNew()
    while (($swInit.ElapsedMilliseconds -lt 6000) -and (-not ($seenEntityState -and $seenWorldState -and $seenWorldChunk))) {
    
    $packet = Read-Packet $stream
    
    if ($packet.Id -eq $EntityStatePacketId) {
    
    
    $entityId = Read-VarInt $packet.Stream
    
    
    $entityType = Read-McString $packet.Stream
    
    
    $entityUser = Read-McString $packet.Stream
    
    
    $health = Read-VarInt $packet.Stream
    
    
    $hunger = Read-VarInt $packet.Stream
    
    
    $aliveRaw = $packet.Stream.ReadByte()
    
    
    if ($entityType -ne $ExpectedEntityType) {
    
    
    
    throw "Entity type mismatch: expected '$ExpectedEntityType', got '$entityType'"
    
    
    }
    
    
    if ($entityUser -ne $ExpectedUsername) {
    
    
    
    throw "Entity username mismatch: expected '$ExpectedUsername', got '$entityUser'"
    
    
    }
    
    
    if ($health -ne 20 -or $hunger -ne 20 -or $aliveRaw -ne 1) {
    
    
    
    throw "Unexpected initial entity state"
    
    
    }
    
    
    $seenEntityState = $true
    
    
    continue
    
    }
    
    if ($packet.Id -eq $WorldStatePacketId) {
    
    
    [void](Read-VarInt $packet.Stream)
    
    
    $worldName = Read-McString $packet.Stream
    
    
    [void](Read-McString $packet.Stream)
    
    
    [void](Read-Exact $packet.Stream 8 * 3)
    
    
    [void](Read-Exact $packet.Stream 4 * 2)
    
    
    [void](Read-Exact $packet.Stream 8)
    
    
    [void]$packet.Stream.ReadByte()
    
    
    if ($worldName -ne $ExpectedWorldName) {
    
    
    
    throw "World name mismatch: expected '$ExpectedWorldName', got '$worldName'"
    
    
    }
    
    
    $seenWorldState = $true
    
    
    continue
    
    }
    
    if ($packet.Id -eq $WorldChunkPacketId) {
    
    
    [void](Read-VarInt $packet.Stream)
    
    
    [void](Read-VarInt $packet.Stream)
    
    
    $blockCount = Read-VarInt $packet.Stream
    
    
    for ($i = 0; $i -lt $blockCount; $i++) {
    
    
    
    [void](Read-VarInt $packet.Stream)
    
    
    
    [void](Read-VarInt $packet.Stream)
    
    
    
    [void](Read-VarInt $packet.Stream)
    
    
    
    [void](Read-VarInt $packet.Stream)
    
    
    }
    
    
    $seenWorldChunk = $true
    
    
    continue
    
    }
    
    if ($packet.Id -eq $DisconnectPacketId) {
    
    
    $disconnectText = Read-AnonymousNbtText $packet.Stream
    
    
    throw "Disconnect before init packets: $disconnectText"
    
    }
    }
    if (-not $seenEntityState) {
    
    throw "Did not receive entity state"
    }
    if (-not $seenWorldState) {
    
    throw "Did not receive world state"
    }
    if (-not $seenWorldChunk) {
    
    throw "Did not receive world chunk"
    }
    if ($entityId -lt 0) {
    
    throw "Invalid entity id"
    }
    $interactPlace = Build-Packet {
    
    param($packetBody)
    
    Write-VarInt $packetBody $InteractActionPacketId
    
    Write-VarInt $packetBody $InteractActionPlace
    
    Write-VarInt $packetBody $InteractX
    
    Write-VarInt $packetBody $InteractY
    
    Write-VarInt $packetBody $InteractZ
    
    Write-VarInt $packetBody $InteractBlockId
    }
    $stream.Write($interactPlace, 0, $interactPlace.Length)
    $combatAttackTarget1 = Build-Packet {
    
    param($packetBody)
    
    Write-VarInt $packetBody $CombatActionPacketId
    
    Write-VarInt $packetBody $CombatActionAttack
    
    Write-VarInt $packetBody $CombatTargetEntityId
    
    Write-VarInt $packetBody 10
    
    Write-VarInt $packetBody $CombatDamageTypeMelee
    }
    $stream.Write($combatAttackTarget1, 0, $combatAttackTarget1.Length)
    Start-Sleep -Milliseconds ($CombatCooldownMs + 100)
    $combatAttackTargetLethal = Build-Packet {
    
    param($packetBody)
    
    Write-VarInt $packetBody $CombatActionPacketId
    
    Write-VarInt $packetBody $CombatActionAttack
    
    Write-VarInt $packetBody $CombatTargetEntityId
    
    Write-VarInt $packetBody 10
    
    Write-VarInt $packetBody $CombatDamageTypeMelee
    }
    $stream.Write($combatAttackTargetLethal, 0, $combatAttackTargetLethal.Length)
    Start-Sleep -Milliseconds ($CombatCooldownMs + 100)
    $combatAttackTargetDeadReject = Build-Packet {
    
    param($packetBody)
    
    Write-VarInt $packetBody $CombatActionPacketId
    
    Write-VarInt $packetBody $CombatActionAttack
    
    Write-VarInt $packetBody $CombatTargetEntityId
    
    Write-VarInt $packetBody 1
    
    Write-VarInt $packetBody $CombatDamageTypeMelee
    }
    $stream.Write($combatAttackTargetDeadReject, 0, $combatAttackTargetDeadReject.Length)
    Start-Sleep -Milliseconds ($CombatRespawnDelayMs + 200)
    $combatAttackTargetProjectile = Build-Packet {
    
    param($packetBody)
    
    Write-VarInt $packetBody $CombatActionPacketId
    
    Write-VarInt $packetBody $CombatActionAttack
    
    Write-VarInt $packetBody $CombatTargetEntityId
    
    Write-VarInt $packetBody 3
    
    Write-VarInt $packetBody $CombatDamageTypeProjectile
    }
    $stream.Write($combatAttackTargetProjectile, 0, $combatAttackTargetProjectile.Length)
    $combatQueryTarget1 = Build-Packet {
    
    param($packetBody)
    
    Write-VarInt $packetBody $CombatActionPacketId
    
    Write-VarInt $packetBody $CombatActionQuery
    
    Write-VarInt $packetBody $CombatTargetEntityId
    
    Write-VarInt $packetBody 0
    }
    $stream.Write($combatQueryTarget1, 0, $combatQueryTarget1.Length)
    Start-Sleep -Milliseconds ($CombatAggroWindowMs + 200)
    $combatQueryTarget2 = Build-Packet {
    
    param($packetBody)
    
    Write-VarInt $packetBody $CombatActionPacketId
    
    Write-VarInt $packetBody $CombatActionQuery
    
    Write-VarInt $packetBody $CombatTargetEntityId
    
    Write-VarInt $packetBody 0
    }
    $stream.Write($combatQueryTarget2, 0, $combatQueryTarget2.Length)
    $seenInteractUpdate = $false
    $seenAttackTarget1 = $false
    $seenTargetLethal = $false
    $seenTargetDeadReject = $false
    $seenTargetProjectile = $false
    $seenTargetQueryAggro = $false
    $seenTargetQueryAggroExpired = $false
    $disconnectReason = ""
    $swTail = [System.Diagnostics.Stopwatch]::StartNew()
    while ($swTail.ElapsedMilliseconds -lt 9000) {
    
    $packet = Read-Packet $stream
    
    if ($packet.Id -eq $InteractUpdatePacketId) {
    
    
    $resultCode = Read-VarInt $packet.Stream
    
    
    $actionType = Read-VarInt $packet.Stream
    
    
    $x = Read-VarInt $packet.Stream
    
    
    $y = Read-VarInt $packet.Stream
    
    
    $z = Read-VarInt $packet.Stream
    
    
    $blockId = Read-VarInt $packet.Stream
    
    
    $changedRaw = $packet.Stream.ReadByte()
    
    
    if ($resultCode -ne 0) {
    
    
    
    throw "Interact update result error: $resultCode"
    
    
    }
    
    
    if ($actionType -ne $InteractActionPlace -or $x -ne $InteractX -or $y -ne $InteractY -or $z -ne $InteractZ) {
    
    
    
    throw "Interact update payload mismatch"
    
    
    }
    
    
    if ($blockId -ne $InteractBlockId) {
    
    
    
    throw "Interact update block mismatch: expected $InteractBlockId got $blockId"
    
    
    }
    
    
    if ($changedRaw -ne 1) {
    
    
    
    throw "Interact changed expected 1, got $changedRaw"
    
    
    }
    
    
    $seenInteractUpdate = $true
    
    
    continue
    
    }
    
    if ($packet.Id -eq $CombatUpdatePacketId) {
    
    
    $resultCode = Read-VarInt $packet.Stream
    
    
    $actionType = Read-VarInt $packet.Stream
    
    
    $updatedEntityId = Read-VarInt $packet.Stream
    
    
    $health = Read-VarInt $packet.Stream
    
    
    [void](Read-VarInt $packet.Stream) # hunger
    
    
    $aliveRaw = $packet.Stream.ReadByte()
    
    
    $totalDamage = Read-VarInt $packet.Stream
    
    
    $deathCount = Read-VarInt $packet.Stream
    
    
    $respawnCount = Read-VarInt $packet.Stream
    
    
    $changedRaw = $packet.Stream.ReadByte()
    
    
    $damageType = if ($packet.Stream.Position -lt $packet.Stream.Length) { Read-VarInt $packet.Stream } else { 0 }
    
    
    $criticalRaw = if ($packet.Stream.Position -lt $packet.Stream.Length) { $packet.Stream.ReadByte() } else { 0 }
    
    
    $appliedDamage = if ($packet.Stream.Position -lt $packet.Stream.Length) { Read-VarInt $packet.Stream } else { 0 }
    
    
    $cooldownRemainingMs = if ($packet.Stream.Position -lt $packet.Stream.Length) { Read-VarInt $packet.Stream } else { 0 }
    
    
    $attackDistance = if ($packet.Stream.Position -lt $packet.Stream.Length) { Read-Double $packet.Stream } else { 0.0 }
    
    
    $targetAliveRaw = if ($packet.Stream.Position -lt $packet.Stream.Length) { $packet.Stream.ReadByte() } else { 0 }
    
    
    $targetHealth = if ($packet.Stream.Position -lt $packet.Stream.Length) { Read-VarInt $packet.Stream } else { 0 }
    
    
    $targetDeathCount = if ($packet.Stream.Position -lt $packet.Stream.Length) { Read-VarInt $packet.Stream } else { 0 }
    
    
    $targetRespawnCount = if ($packet.Stream.Position -lt $packet.Stream.Length) { Read-VarInt $packet.Stream } else { 0 }
    
    
    $targetRespawnRemainingMs = if ($packet.Stream.Position -lt $packet.Stream.Length) { Read-VarInt $packet.Stream } else { 0 }
    
    
    $targetAggroRemainingMs = if ($packet.Stream.Position -lt $packet.Stream.Length) { Read-VarInt $packet.Stream } else { 0 }
    
    
    if ($actionType -eq $CombatActionAttack) {
    
    
    
    if ($updatedEntityId -eq $CombatTargetEntityId) {
    
    
    
    
    if ($resultCode -eq 0 -and $health -eq 10 -and $aliveRaw -eq 1 -and $changedRaw -eq 1 -and $damageType -eq $CombatDamageTypeMelee -and $appliedDamage -eq 10 -and $targetAliveRaw -eq 1 -and $targetHealth -eq 10 -and $targetAggroRemainingMs -gt 0) {
    
    
    
    
    
    $seenAttackTarget1 = $true
    
    
    
    
    
    continue
    
    
    
    
    }
    
    
    
    
    if ($resultCode -eq 0 -and $health -eq 0 -and $aliveRaw -eq 0 -and $changedRaw -eq 1 -and $damageType -eq $CombatDamageTypeMelee -and $appliedDamage -eq 10 -and $targetAliveRaw -eq 0 -and $targetDeathCount -ge 1 -and $targetRespawnRemainingMs -gt 0) {
    
    
    
    
    
    $seenTargetLethal = $true
    
    
    
    
    
    continue
    
    
    
    
    }
    
    
    
    
    if ($resultCode -eq 9 -and $changedRaw -eq 0 -and $damageType -eq $CombatDamageTypeMelee -and $targetAliveRaw -eq 0) {
    
    
    
    
    
    $seenTargetDeadReject = $true
    
    
    
    
    
    continue
    
    
    
    
    }
    
    
    
    
    if ($resultCode -eq 0 -and $health -eq 14 -and $aliveRaw -eq 1 -and $changedRaw -eq 1 -and $damageType -eq $CombatDamageTypeProjectile -and $criticalRaw -eq 0 -and $appliedDamage -eq 6 -and $targetAliveRaw -eq 1 -and $targetHealth -eq 14 -and $targetRespawnCount -ge 1 -and $targetAggroRemainingMs -gt 0) {
    
    
    
    
    
    $seenTargetProjectile = $true
    
    
    
    
    
    continue
    
    
    
    
    }
    
    
    
    
    throw "Unexpected target attack update: result=$resultCode entity=$updatedEntityId changed=$changedRaw damageType=$damageType health=$health targetAlive=$targetAliveRaw targetRespawnRemaining=$targetRespawnRemainingMs"
    
    
    
    }
    
    
    
    throw "Combat attack update for unknown entity: $updatedEntityId"
    
    
    }
    
    
    if ($actionType -eq $CombatActionQuery) {
    
    
    
    if ($updatedEntityId -ne $CombatTargetEntityId) {
    
    
    
    
    throw "Query update entity mismatch: expected $CombatTargetEntityId got $updatedEntityId"
    
    
    
    }
    
    
    
    if ($resultCode -ne 0) {
    
    
    
    
    throw "Query update result error: $resultCode"
    
    
    
    }
    
    
    
    if ($health -ne 14 -or $aliveRaw -ne 1 -or $targetAliveRaw -ne 1 -or $targetHealth -ne 14) {
    
    
    
    
    throw "Query update expected target health=14 alive=1, got health=$health alive=$aliveRaw targetAlive=$targetAliveRaw targetHealth=$targetHealth"
    
    
    
    }
    
    
    
    if ($targetDeathCount -lt 1 -or $targetRespawnCount -lt 1) {
    
    
    
    
    throw "Query update expected target death/respawn counters >= 1, got deaths=$targetDeathCount respawns=$targetRespawnCount"
    
    
    
    }
    
    
    
    if ($targetAggroRemainingMs -gt 0) {
    
    
    
    
    $seenTargetQueryAggro = $true
    
    
    
    
    continue
    
    
    
    }
    
    
    
    if ($targetAggroRemainingMs -eq 0) {
    
    
    
    
    $seenTargetQueryAggroExpired = $true
    
    
    
    
    continue
    
    
    
    }
    
    
    }
    
    
    throw "Unexpected combat action type in update: $actionType"
    
    }
    
    if ($packet.Id -eq $DisconnectPacketId) {
    
    
    $disconnectReason = Read-AnonymousNbtText $packet.Stream
    
    
    break
    
    }
    }
    if (-not $seenInteractUpdate) {
    
    throw "Did not receive interact update"
    }
    if (-not $seenAttackTarget1) {
    
    throw "Did not receive first target attack update"
    }
    if (-not $seenTargetLethal) {
    
    throw "Did not receive target lethal update"
    }
    if (-not $seenTargetDeadReject) {
    
    throw "Did not receive target dead reject update"
    }
    if (-not $seenTargetProjectile) {
    
    throw "Did not receive projectile target update after respawn"
    }
    if (-not $seenTargetQueryAggro) {
    
    throw "Did not receive target query with active aggro window"
    }
    if (-not $seenTargetQueryAggroExpired) {
    
    throw "Did not receive target query after aggro window expired"
    }
    if ([string]::IsNullOrWhiteSpace($disconnectReason)) {
    
    throw "Did not receive disconnect reason"
    }
    if (-not $disconnectReason.Contains("interact-actions=1")) {
    
    throw "Disconnect reason missing interact-actions=1: $disconnectReason"
    }
    if (-not $disconnectReason.Contains("combat-actions=6")) {
    
    throw "Disconnect reason missing combat-actions=6: $disconnectReason"
    }
    if (-not $disconnectReason.Contains("combat-attack-actions=4")) {
    
    throw "Disconnect reason missing combat-attack-actions=4: $disconnectReason"
    }
    if (-not $disconnectReason.Contains("combat-query-actions=2")) {
    
    throw "Disconnect reason missing combat-query-actions=2: $disconnectReason"
    }
    if (-not $disconnectReason.Contains("combat-target-dead-rejects=1")) {
    
    throw "Disconnect reason missing combat-target-dead-rejects=1: $disconnectReason"
    }
    if (-not $disconnectReason.Contains("combat-damage-type-rejects=0")) {
    
    throw "Disconnect reason missing combat-damage-type-rejects=0: $disconnectReason"
    }
    if (-not $disconnectReason.Contains("combat-target-deaths=1")) {
    
    throw "Disconnect reason missing combat-target-deaths=1: $disconnectReason"
    }
    if (-not $disconnectReason.Contains("combat-target-respawns=1")) {
    
    throw "Disconnect reason missing combat-target-respawns=1: $disconnectReason"
    }
    if (-not $disconnectReason.Contains("combat-target-health=14")) {
    
    throw "Disconnect reason missing combat-target-health=14: $disconnectReason"
    }
    if (-not $disconnectReason.Contains("combat-target-aggro-active=false")) {
    
    throw "Disconnect reason missing combat-target-aggro-active=false: $disconnectReason"
    }
    if (-not $disconnectReason.Contains("combat-target-entity-id=$CombatTargetEntityId")) {
    
    throw "Disconnect reason missing combat-target-entity-id=${CombatTargetEntityId}: $disconnectReason"
    }
    Write-Host "E2E_PLAY_COMBAT_LIFECYCLE_OK"
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
