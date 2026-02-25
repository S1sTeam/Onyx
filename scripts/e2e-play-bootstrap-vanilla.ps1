param(
    [string]$JavaBinary = "java",
    [string]$DistPath = "dist",
    [int]$BackendPort = 33566 )
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$Protocol = 769
$DisconnectPacketId = 0x1D
$LoginAckPacketId = 0x03
$ConfigFinishPacketId = 0x03
$BootstrapInitPacketId = 0x6A
$BootstrapSpawnPacketId = 0x6B
$BootstrapMessagePacketId = 0x6C
$ExpectedUsername = "VanillaBootstrap"
$ExpectedMessage = "Onyx vanilla bootstrap"
$ExpectedX = 18.25
$ExpectedY = 72.0
$ExpectedZ = -6.5
$ExpectedYaw = 90.0
$ExpectedPitch = 15.0
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
function Read-IntBE([System.IO.Stream]$stream) {
    $bytes = Read-Exact $stream 4
    [Array]::Reverse($bytes)
    return [System.BitConverter]::ToInt32($bytes, 0)}
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
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-protocol-mode\s*=.*$' -line "play-protocol-mode = onyx"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-enabled\s*=.*$' -line "play-session-enabled = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-duration-ms\s*=.*$' -line "play-session-duration-ms = 400"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-poll-timeout-ms\s*=.*$' -line "play-session-poll-timeout-ms = 50"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-max-packets\s*=.*$' -line "play-session-max-packets = 128"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-disconnect-on-limit\s*=.*$' -line "play-session-disconnect-on-limit = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-enabled\s*=.*$' -line "play-bootstrap-enabled = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-format\s*=.*$' -line "play-bootstrap-format = vanilla-minimal"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-init-packet-id\s*=.*$' -line "play-bootstrap-init-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-spawn-packet-id\s*=.*$' -line "play-bootstrap-spawn-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-message-packet-id\s*=.*$' -line "play-bootstrap-message-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-spawn-x\s*=.*$' -line "play-bootstrap-spawn-x = $ExpectedX"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-spawn-y\s*=.*$' -line "play-bootstrap-spawn-y = $ExpectedY"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-spawn-z\s*=.*$' -line "play-bootstrap-spawn-z = $ExpectedZ"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-yaw\s*=.*$' -line "play-bootstrap-yaw = $ExpectedYaw"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-pitch\s*=.*$' -line "play-bootstrap-pitch = $ExpectedPitch"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-message\s*=.*$' -line "play-bootstrap-message = $ExpectedMessage"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-ack-enabled\s*=.*$' -line "play-bootstrap-ack-enabled = false"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-movement-enabled\s*=.*$' -line "play-movement-enabled = false"
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
    [void](Read-Exact $loginSuccess.Stream 16) # UUID
    $username = Read-McString $loginSuccess.Stream
    if ($username -ne $ExpectedUsername) {
    
    throw "Unexpected username in login success: $username"
    }
    $propertyCount = Read-VarInt $loginSuccess.Stream
    if ($propertyCount -ne 0) {
    
    throw "Unexpected login property count: $propertyCount"
    }
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
    $gotInit = $false
    $gotSpawn = $false
    $gotMessage = $false
    $disconnectReason = ""
    $maxPackets = 128
    for ($i = 0; $i -lt $maxPackets; $i++) {
    
    $packet = Read-Packet $stream
    
    if ($packet.Id -eq $BootstrapInitPacketId) {
    
    
    $entityId = Read-IntBE $packet.Stream
    
    
    $hardcore = $packet.Stream.ReadByte()
    
    
    $gameMode = $packet.Stream.ReadByte()
    
    
    $prevGameMode = $packet.Stream.ReadByte()
    
    
    $worldCount = Read-VarInt $packet.Stream
    
    
    $worldName = Read-McString $packet.Stream
    
    
    $maxPlayers = Read-VarInt $packet.Stream
    
    
    $viewDistance = Read-VarInt $packet.Stream
    
    
    $simulationDistance = Read-VarInt $packet.Stream
    
    
    [void]$packet.Stream.ReadByte()
    
    
    [void]$packet.Stream.ReadByte()
    
    
    [void]$packet.Stream.ReadByte()
    
    
    [void](Read-LongBE $packet.Stream)
    
    
    $spawnX = Read-DoubleBE $packet.Stream
    
    
    $spawnY = Read-DoubleBE $packet.Stream
    
    
    $spawnZ = Read-DoubleBE $packet.Stream
    
    
    $yaw = Read-FloatBE $packet.Stream
    
    
    $pitch = Read-FloatBE $packet.Stream
    
    
    $protocolEcho = Read-VarInt $packet.Stream
    
    
    $bootstrapUser = Read-McString $packet.Stream
    
    
    $ackToken = Read-VarInt $packet.Stream
    
    
    if ($entityId -ne 1) {
    
    
    
    throw "Unexpected vanilla init entity id: $entityId"
    
    
    }
    
    
    if ($hardcore -ne 0) {
    
    
    
    throw "Unexpected hardcore flag: $hardcore"
    
    
    }
    
    
    if ($gameMode -ne 0) {
    
    
    
    throw "Unexpected gamemode: $gameMode"
    
    
    }
    
    
    if ($prevGameMode -ne 255) {
    
    
    
    throw "Unexpected previous gamemode: $prevGameMode"
    
    
    }
    
    
    if ($worldCount -ne 1 -or $worldName -ne "onyx:world") {
    
    
    
    throw "Unexpected world bootstrap section: count=$worldCount world=$worldName"
    
    
    }
    
    
    if ($maxPlayers -lt 1) {
    
    
    
    throw "Unexpected max players field: $maxPlayers"
    
    
    }
    
    
    if ($viewDistance -ne 8 -or $simulationDistance -ne 8) {
    
    
    
    throw "Unexpected view/simulation distance: $viewDistance/$simulationDistance"
    
    
    }
    
    
    if ([math]::Abs($spawnX - $ExpectedX) -gt 0.0001 -or [math]::Abs($spawnY - $ExpectedY) -gt 0.0001 -or [math]::Abs($spawnZ - $ExpectedZ) -gt 0.0001) {
    
    
    
    throw "Unexpected vanilla init spawn coordinates: $spawnX $spawnY $spawnZ"
    
    
    }
    
    
    if ([math]::Abs($yaw - $ExpectedYaw) -gt 0.0001 -or [math]::Abs($pitch - $ExpectedPitch) -gt 0.0001) {
    
    
    
    throw "Unexpected vanilla init rotation: $yaw $pitch"
    
    
    }
    
    
    if ($protocolEcho -ne $Protocol) {
    
    
    
    throw "Unexpected protocol echo in vanilla init: $protocolEcho"
    
    
    }
    
    
    if ($bootstrapUser -ne $ExpectedUsername) {
    
    
    
    throw "Unexpected bootstrap username: $bootstrapUser"
    
    
    }
    
    
    if ($ackToken -lt 0) {
    
    
    
    throw "Invalid ack token value: $ackToken"
    
    
    }
    
    
    $gotInit = $true
    
    
    continue
    
    }
    
    if ($packet.Id -eq $BootstrapSpawnPacketId) {
    
    
    $x = Read-DoubleBE $packet.Stream
    
    
    $y = Read-DoubleBE $packet.Stream
    
    
    $z = Read-DoubleBE $packet.Stream
    
    
    $yaw = Read-FloatBE $packet.Stream
    
    
    $pitch = Read-FloatBE $packet.Stream
    
    
    $flags = $packet.Stream.ReadByte()
    
    
    $teleportId = Read-VarInt $packet.Stream
    
    
    $dismount = $packet.Stream.ReadByte()
    
    
    if ([math]::Abs($x - $ExpectedX) -gt 0.0001 -or [math]::Abs($y - $ExpectedY) -gt 0.0001 -or [math]::Abs($z - $ExpectedZ) -gt 0.0001) {
    
    
    
    throw "Unexpected vanilla spawn coordinates: $x $y $z"
    
    
    }
    
    
    if ([math]::Abs($yaw - $ExpectedYaw) -gt 0.0001 -or [math]::Abs($pitch - $ExpectedPitch) -gt 0.0001) {
    
    
    
    throw "Unexpected vanilla spawn rotation: $yaw $pitch"
    
    
    }
    
    
    if ($flags -ne 0 -or $teleportId -ne 0 -or $dismount -ne 0) {
    
    
    
    throw "Unexpected spawn transport fields: flags=$flags teleportId=$teleportId dismount=$dismount"
    
    
    }
    
    
    $gotSpawn = $true
    
    
    continue
    
    }
    
    if ($packet.Id -eq $BootstrapMessagePacketId) {
    
    
    $jsonMessage = Read-McString $packet.Stream
    
    
    $actionBar = $packet.Stream.ReadByte()
    
    
    if ($jsonMessage -notmatch '"text"') {
    
    
    
    throw "Unexpected vanilla bootstrap message JSON: $jsonMessage"
    
    
    }
    
    
    if ($actionBar -ne 0) {
    
    
    
    throw "Unexpected action bar flag: $actionBar"
    
    
    }
    
    
    $gotMessage = $true
    
    
    continue
    
    }
    
    if ($packet.Id -eq $DisconnectPacketId) {
    
    
    $disconnectReason = Read-AnonymousNbtText $packet.Stream
    
    
    break
    
    }
    }
    if (-not $gotInit) {
    
    throw "Vanilla bootstrap init packet not received"
    }
    if (-not $gotSpawn) {
    
    throw "Vanilla bootstrap spawn packet not received"
    }
    if (-not $gotMessage) {
    
    throw "Vanilla bootstrap message packet not received"
    }
    if ([string]::IsNullOrWhiteSpace($disconnectReason)) {
    
    throw "Did not receive final disconnect packet"
    }
    if ($disconnectReason -notmatch 'bootstrap-sent=3') {
    
    throw "Disconnect reason does not include bootstrap metric: $disconnectReason"
    }
    Write-Host "[ONYX] E2E_PLAY_BOOTSTRAP_VANILLA_OK"
    Write-Host "[ONYX] DISCONNECT_REASON=$disconnectReason"
} finally {
    if ($client -ne $null) {
    
    $client.Close()
    }
    Stop-JavaProcess -proc $server -stopCommand "stop"
    if ($null -ne $originalServerConfig) {
    
    Set-Content -Path $serverConfigPath -Value $originalServerConfig -Encoding UTF8 -NoNewline
    }}
