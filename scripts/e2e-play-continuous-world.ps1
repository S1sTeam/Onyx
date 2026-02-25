param(
    [string]$JavaBinary = "java",
    [string]$DistPath = "dist",
    [int]$BackendPort = 41666 )
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$Protocol = 769
$DisconnectPacketId = 0x1D
$LoginAckPacketId = 0x03
$ConfigFinishPacketId = 0x03
$WorldStatePacketId = 0x75
$WorldChunkPacketId = 0x76
$WorldActionPacketId = 0x77
$WorldBlockUpdatePacketId = 0x78
$ExpectedUsername = "WorldContProbe"
$ExpectedWorldName = "onyx:world"
$ExpectedInitialChunks = 9
$ExpectedChunkX = 2
$ExpectedChunkZ = 2
$ActionTypeSet = 0
$ActionX = 40
$ActionY = 66
$ActionZ = 40
$ActionBlockId = 5
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
function Read-LongBE([System.IO.Stream]$stream) {
    $bytes = Read-Exact $stream 8
    [Array]::Reverse($bytes)
    return [System.BitConverter]::ToInt64($bytes, 0)}
function Read-DoubleBE([System.IO.Stream]$stream) {
    $bytes = Read-Exact $stream 8
    [Array]::Reverse($bytes)
    return [System.BitConverter]::ToDouble($bytes, 0)}
function Read-FloatBE([System.IO.Stream]$stream) {
    $bytes = Read-Exact $stream 4
    [Array]::Reverse($bytes)
    return [System.BitConverter]::ToSingle($bytes, 0)}
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
function Read-PacketSafe([System.IO.Stream]$stream, [string]$stage) {
    try {
    
    return Read-Packet $stream
    } catch {
    
    throw "Read-Packet failed at ${stage}: $($_.Exception.Message)"
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
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-enabled\s*=.*$' -line "play-session-enabled = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-duration-ms\s*=.*$' -line "play-session-duration-ms = 200"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-poll-timeout-ms\s*=.*$' -line "play-session-poll-timeout-ms = 40"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-max-packets\s*=.*$' -line "play-session-max-packets = 2"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-idle-timeout-ms\s*=.*$' -line "play-session-idle-timeout-ms = 1100"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-persistent\s*=.*$' -line "play-session-persistent = false"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-disconnect-on-limit\s*=.*$' -line "play-session-disconnect-on-limit = false"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-enabled\s*=.*$' -line "play-bootstrap-enabled = false"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-movement-enabled\s*=.*$' -line "play-movement-enabled = false"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-input-enabled\s*=.*$' -line "play-input-enabled = false"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-world-enabled\s*=.*$' -line "play-world-enabled = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-world-state-packet-id\s*=.*$' -line "play-world-state-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-world-chunk-packet-id\s*=.*$' -line "play-world-chunk-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-world-action-packet-id\s*=.*$' -line "play-world-action-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-world-block-update-packet-id\s*=.*$' -line "play-world-block-update-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-world-view-distance\s*=.*$' -line "play-world-view-distance = 1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-world-send-chunk-updates\s*=.*$' -line "play-world-send-chunk-updates = true"
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
    $loginSuccess = Read-PacketSafe $stream "login-success"
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
    $configFinish = Read-PacketSafe $stream "config-finish"
    if ($configFinish.Id -ne $ConfigFinishPacketId) {
    
    throw "Expected config finish packet ($ConfigFinishPacketId), got $($configFinish.Id)"
    }
    $clientFinish = Build-Packet {
    
    param($packetBody)
    
    Write-VarInt $packetBody $ConfigFinishPacketId
    }
    $stream.Write($clientFinish, 0, $clientFinish.Length)
    $seenWorldState = $false
    $worldChunkPackets = 0
    $swInit = [System.Diagnostics.Stopwatch]::StartNew()
    while (($swInit.ElapsedMilliseconds -lt 5000) -and ($worldChunkPackets -lt $ExpectedInitialChunks)) {
    
    $packet = Read-PacketSafe $stream "world-init"
    
    if ($packet.Id -eq $WorldStatePacketId) {
    
    
    $stateProtocol = Read-VarInt $packet.Stream
    
    
    $worldName = Read-McString $packet.Stream
    
    
    $stateUsername = Read-McString $packet.Stream
    
    
    [void](Read-DoubleBE $packet.Stream)
    
    
    [void](Read-DoubleBE $packet.Stream)
    
    
    [void](Read-DoubleBE $packet.Stream)
    
    
    [void](Read-FloatBE $packet.Stream)
    
    
    [void](Read-FloatBE $packet.Stream)
    
    
    [void](Read-LongBE $packet.Stream)
    
    
    [void]$packet.Stream.ReadByte()
    
    
    if ($stateProtocol -ne $Protocol) {
    
    
    
    throw "World state protocol mismatch: expected $Protocol, got $stateProtocol"
    
    
    }
    
    
    if ($worldName -ne $ExpectedWorldName) {
    
    
    
    throw "World name mismatch: expected '$ExpectedWorldName', got '$worldName'"
    
    
    }
    
    
    if ($stateUsername -ne $ExpectedUsername) {
    
    
    
    throw "World state username mismatch: expected '$ExpectedUsername', got '$stateUsername'"
    
    
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
    
    
    $worldChunkPackets++
    
    
    continue
    
    }
    
    if ($packet.Id -eq $DisconnectPacketId) {
    
    
    $disconnectText = Read-AnonymousNbtText $packet.Stream
    
    
    throw "Received disconnect before world init packets: $disconnectText"
    
    }
    }
    if (-not $seenWorldState) {
    
    throw "Did not receive world state packet"
    }
    if ($worldChunkPackets -lt $ExpectedInitialChunks) {
    
    throw "Initial world chunk stream is incomplete: expected at least $ExpectedInitialChunks, got $worldChunkPackets"
    }
    Start-Sleep -Milliseconds 350
    $worldAction = Build-Packet {
    
    param($packetBody)
    
    Write-VarInt $packetBody $WorldActionPacketId
    
    Write-VarInt $packetBody $ActionTypeSet
    
    Write-VarInt $packetBody $ActionX
    
    Write-VarInt $packetBody $ActionY
    
    Write-VarInt $packetBody $ActionZ
    
    Write-VarInt $packetBody $ActionBlockId
    }
    $stream.Write($worldAction, 0, $worldAction.Length)
    $receivedWorldUpdate = $false
    $receivedChunkRefresh = $false
    $disconnectReason = ""
    $swTail = [System.Diagnostics.Stopwatch]::StartNew()
    while ($swTail.ElapsedMilliseconds -lt 5000) {
    
    $packet = Read-PacketSafe $stream "world-tail"
    
    if ($packet.Id -eq $WorldBlockUpdatePacketId) {
    
    
    $resultCode = Read-VarInt $packet.Stream
    
    
    $actionType = Read-VarInt $packet.Stream
    
    
    $x = Read-VarInt $packet.Stream
    
    
    $y = Read-VarInt $packet.Stream
    
    
    $z = Read-VarInt $packet.Stream
    
    
    $blockId = Read-VarInt $packet.Stream
    
    
    $changedRaw = $packet.Stream.ReadByte()
    
    
    if ($changedRaw -lt 0) {
    
    
    
    throw "Unexpected EOF while reading world update changed flag"
    
    
    }
    
    
    if ($resultCode -ne 0) {
    
    
    
    throw "World update result is not success: $resultCode"
    
    
    }
    
    
    if ($actionType -ne $ActionTypeSet) {
    
    
    
    throw "World update action mismatch: expected $ActionTypeSet, got $actionType"
    
    
    }
    
    
    if ($x -ne $ActionX -or $y -ne $ActionY -or $z -ne $ActionZ) {
    
    
    
    throw "World update coords mismatch: expected $ActionX/$ActionY/$ActionZ, got $x/$y/$z"
    
    
    }
    
    
    if ($blockId -ne $ActionBlockId) {
    
    
    
    throw "World update block id mismatch: expected $ActionBlockId, got $blockId"
    
    
    }
    
    
    if ($changedRaw -ne 1) {
    
    
    
    throw "World update expected changed=1, got $changedRaw"
    
    
    }
    
    
    $receivedWorldUpdate = $true
    
    
    continue
    
    }
    
    if ($packet.Id -eq $WorldChunkPacketId) {
    
    
    $chunkX = Read-VarInt $packet.Stream
    
    
    $chunkZ = Read-VarInt $packet.Stream
    
    
    $blockCount = Read-VarInt $packet.Stream
    
    
    for ($i = 0; $i -lt $blockCount; $i++) {
    
    
    
    [void](Read-VarInt $packet.Stream)
    
    
    
    [void](Read-VarInt $packet.Stream)
    
    
    
    [void](Read-VarInt $packet.Stream)
    
    
    
    [void](Read-VarInt $packet.Stream)
    
    
    }
    
    
    if ($chunkX -eq $ExpectedChunkX -and $chunkZ -eq $ExpectedChunkZ) {
    
    
    
    $receivedChunkRefresh = $true
    
    
    }
    
    
    continue
    
    }
    
    if ($packet.Id -eq $DisconnectPacketId) {
    
    
    $disconnectReason = Read-AnonymousNbtText $packet.Stream
    
    
    break
    
    }
    }
    if (-not $receivedWorldUpdate) {
    
    throw "Did not receive world block update packet"
    }
    if (-not $receivedChunkRefresh) {
    
    throw "Did not receive refreshed chunk for changed block chunk ($ExpectedChunkX,$ExpectedChunkZ)"
    }
    Write-Host "[ONYX] E2E_PLAY_CONTINUOUS_WORLD_OK"
    Write-Host "[ONYX] INITIAL_CHUNKS=$worldChunkPackets"
    if (-not [string]::IsNullOrWhiteSpace($disconnectReason)) {
    
    Write-Host "[ONYX] DISCONNECT_REASON=$disconnectReason"
    }} finally {
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