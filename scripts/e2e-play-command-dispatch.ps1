param(
    [string]$JavaBinary = "java",
    [string]$DistPath = "dist",
    [int]$BackendPort = 41566 )
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$Protocol = 769
$DisconnectPacketId = 0x1D
$LoginAckPacketId = 0x03
$ConfigFinishPacketId = 0x03
$CommandPacketId = 0x74
$PositionRotationPacketId = 0x71
$ResponsePacketId = 0x6C
$ExpectedUsername = "CmdDispatchProbe"
$MoveX = 12.25
$MoveY = 66.0
$MoveZ = -8.5
$MoveYaw = 90.0
$MovePitch = 10.5
$ExpectedResponsePing = "Onyx pong"
$ExpectedResponseWhere = "Onyx where 12.250/66.000/-8.500 rot 90.000/10.500 onGround=true"
$ExpectedResponseEcho = "Onyx echo: hello world"
$ExpectedResponseUnknown = "Onyx unknown command"
function Write-VarInt([System.IO.Stream]$stream, [int]$value) {
    $v = [uint32]$value
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
function Read-IntBE([System.IO.Stream]$stream) {
    $bytes = Read-Exact $stream 4
    [Array]::Reverse($bytes)
    return [System.BitConverter]::ToInt32($bytes, 0)}
function Read-DoubleBE([System.IO.Stream]$stream) {
    $bytes = Read-Exact $stream 8
    [Array]::Reverse($bytes)
    return [System.BitConverter]::ToDouble($bytes, 0)}
function Write-DoubleBE([System.IO.Stream]$stream, [double]$value) {
    $bytes = [System.BitConverter]::GetBytes([double]$value)
    [Array]::Reverse($bytes)
    $stream.Write($bytes, 0, $bytes.Length)}
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
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-enabled\s*=.*$' -line "play-session-enabled = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-duration-ms\s*=.*$' -line "play-session-duration-ms = 1000"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-poll-timeout-ms\s*=.*$' -line "play-session-poll-timeout-ms = 50"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-max-packets\s*=.*$' -line "play-session-max-packets = 128"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-disconnect-on-limit\s*=.*$' -line "play-session-disconnect-on-limit = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-enabled\s*=.*$' -line "play-bootstrap-enabled = false"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-format\s*=.*$' -line "play-bootstrap-format = onyx"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-message-packet-id\s*=.*$' -line "play-bootstrap-message-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-movement-enabled\s*=.*$' -line "play-movement-enabled = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-movement-teleport-confirm-packet-id\s*=.*$' -line "play-movement-teleport-confirm-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-movement-position-packet-id\s*=.*$' -line "play-movement-position-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-movement-rotation-packet-id\s*=.*$' -line "play-movement-rotation-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-movement-position-rotation-packet-id\s*=.*$' -line "play-movement-position-rotation-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-movement-on-ground-packet-id\s*=.*$' -line "play-movement-on-ground-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-movement-require-teleport-confirm\s*=.*$' -line "play-movement-require-teleport-confirm = false"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-input-enabled\s*=.*$' -line "play-input-enabled = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-input-chat-packet-id\s*=.*$' -line "play-input-chat-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-input-command-packet-id\s*=.*$' -line "play-input-command-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-input-max-message-length\s*=.*$' -line "play-input-max-message-length = 64"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-input-response-enabled\s*=.*$' -line "play-input-response-enabled = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-input-response-packet-id\s*=.*$' -line "play-input-response-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-input-response-prefix\s*=.*$' -line "play-input-response-prefix = Onyx"
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
    $movementPacket = Build-Packet {
    
    param($packetBody)
    
    Write-VarInt $packetBody $PositionRotationPacketId
    
    Write-DoubleBE $packetBody $MoveX
    
    Write-DoubleBE $packetBody $MoveY
    
    Write-DoubleBE $packetBody $MoveZ
    
    $yawBytes = [System.BitConverter]::GetBytes([single]$MoveYaw); [Array]::Reverse($yawBytes); $packetBody.Write($yawBytes,0,4)
    
    $pitchBytes = [System.BitConverter]::GetBytes([single]$MovePitch); [Array]::Reverse($pitchBytes); $packetBody.Write($pitchBytes,0,4)
    
    $packetBody.WriteByte(1)
    }
    $stream.Write($movementPacket, 0, $movementPacket.Length)
    $commandPingPacket = Build-Packet {
    
    param($packetBody)
    
    Write-VarInt $packetBody $CommandPacketId
    
    Write-McString $packetBody "ping"
    }
    $stream.Write($commandPingPacket, 0, $commandPingPacket.Length)
    $commandWherePacket = Build-Packet {
    
    param($packetBody)
    
    Write-VarInt $packetBody $CommandPacketId
    
    Write-McString $packetBody "where"
    }
    $stream.Write($commandWherePacket, 0, $commandWherePacket.Length)
    $commandEchoPacket = Build-Packet {
    
    param($packetBody)
    
    Write-VarInt $packetBody $CommandPacketId
    
    Write-McString $packetBody "echo hello world"
    }
    $stream.Write($commandEchoPacket, 0, $commandEchoPacket.Length)
    $commandUnknownPacket = Build-Packet {
    
    param($packetBody)
    
    Write-VarInt $packetBody $CommandPacketId
    
    Write-McString $packetBody "abracadabra"
    }
    $stream.Write($commandUnknownPacket, 0, $commandUnknownPacket.Length)
    $sentCommands = 4
    $receivedPingResponse = $false
    $receivedWhereResponse = $false
    $receivedEchoResponse = $false
    $receivedUnknownResponse = $false
    $disconnectReason = ""
    $maxPackets = 128
    for ($i = 0; $i -lt $maxPackets; $i++) {
    
    $packet = Read-Packet $stream
    
    if ($packet.Id -eq $ResponsePacketId) {
    
    
    $responseText = Read-McString $packet.Stream
    
    
    if ($responseText -eq $ExpectedResponsePing) {
    
    
    
    $receivedPingResponse = $true
    
    
    }
    
    
    if ($responseText -eq $ExpectedResponseWhere) {
    
    
    
    $receivedWhereResponse = $true
    
    
    }
    
    
    if ($responseText -eq $ExpectedResponseEcho) {
    
    
    
    $receivedEchoResponse = $true
    
    
    }
    
    
    if ($responseText -eq $ExpectedResponseUnknown) {
    
    
    
    $receivedUnknownResponse = $true
    
    
    }
    
    
    continue
    
    }
    
    if ($packet.Id -eq $DisconnectPacketId) {
    
    
    $disconnectReason = Read-AnonymousNbtText $packet.Stream
    
    
    break
    
    }
    }
    if ($sentCommands -ne 4) {
    
    throw "Command packets were not fully sent"
    }
    if ([string]::IsNullOrWhiteSpace($disconnectReason)) {
    
    throw "Did not receive final disconnect packet"
    }
    if ($disconnectReason -notmatch 'input-packets=4') {
    
    throw "Server did not report input packet total: $disconnectReason"
    }
    if ($disconnectReason -notmatch 'input-chat-packets=0') {
    
    throw "Server did not report zero chat packets: $disconnectReason"
    }
    if ($disconnectReason -notmatch 'input-command-packets=4') {
    
    throw "Server did not record command packet: $disconnectReason"
    }
    if ($disconnectReason -notmatch 'input-response-packets=4') {
    
    throw "Server did not record input response packet count: $disconnectReason"
    }
    if ($disconnectReason -notmatch 'input-command-ping=1') {
    
    throw "Server did not record ping command count: $disconnectReason"
    }
    if ($disconnectReason -notmatch 'input-command-where=1') {
    
    throw "Server did not record where command count: $disconnectReason"
    }
    if ($disconnectReason -notmatch 'input-command-help=0') {
    
    throw "Server did not record help command count: $disconnectReason"
    }
    if ($disconnectReason -notmatch 'input-command-echo=1') {
    
    throw "Server did not record echo command count: $disconnectReason"
    }
    if ($disconnectReason -notmatch 'input-command-unknown=1') {
    
    throw "Server did not record unknown command count: $disconnectReason"
    }
    if ($disconnectReason -notmatch 'input-last-command=abracadabra') {
    
    throw "Server did not report expected last command: $disconnectReason"
    }
    if (-not $receivedPingResponse) {
    
    throw "Did not receive expected ping response"
    }
    if (-not $receivedWhereResponse) {
    
    throw "Did not receive expected where response"
    }
    if (-not $receivedEchoResponse) {
    
    throw "Did not receive expected echo response"
    }
    if (-not $receivedUnknownResponse) {
    
    throw "Did not receive expected unknown-command response"
    }
    Write-Host "[ONYX] E2E_PLAY_COMMAND_DISPATCH_OK"
    Write-Host "[ONYX] DISCONNECT_REASON=$disconnectReason"
} finally {
    if ($client -ne $null) {
    
    $client.Close()
    }
    Stop-JavaProcess -proc $server -stopCommand "stop"
    if ($null -ne $originalServerConfig) {
    
    Set-Content -Path $serverConfigPath -Value $originalServerConfig -Encoding UTF8 -NoNewline
    }}