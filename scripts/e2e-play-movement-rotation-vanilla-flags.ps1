param(
    [string]$JavaBinary = "java",
    [string]$DistPath = "dist",
    [int]$BackendPort = 35566,
    [int]$Protocol = 769,
    [int]$DisconnectPacketId = 0x1D,
    [int]$LoginAckPacketId = 0x03,
    [int]$ConfigFinishPacketId = 0x03,
    [int]$BootstrapInitPacketId = 0x2C,
    [int]$BootstrapSpawnPacketId = 0x42,
    [int]$BootstrapMessagePacketId = 0x73,
    [int]$TeleportConfirmPacketId = 0x00,
    [int]$RotationPacketId = 0x1E,
    [int]$PositionRotationPacketId = 0x1D,
    [int]$ExpectedTeleportId = 77,
    [string]$ExpectedUsername = "MoveRotProbe",
    [double]$SpawnX = 2.0,
    [double]$SpawnY = 70.0,
    [double]$SpawnZ = 2.0,
    [double]$FinalX = 5.5,
    [double]$FinalY = 71.25,
    [double]$FinalZ = 3.0,
    [double]$FinalYaw = 179.75,
    [double]$FinalPitch = 2.5
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$MovementFlags = 0x02
if ([string]::IsNullOrWhiteSpace($ExpectedUsername)) {
    throw "ExpectedUsername must not be empty."
}
if ($ExpectedUsername.Length -gt 16) {
    throw "ExpectedUsername exceeds 16 characters: $ExpectedUsername"
}
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
function Write-FloatBE([System.IO.Stream]$stream, [float]$value) {
    $bytes = [System.BitConverter]::GetBytes([single]$value)
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
    if ($null -eq $proc) { return }
    if ($proc.HasExited) { return }
    try {
    
    $proc.StandardInput.WriteLine($stopCommand)
    
    $proc.StandardInput.Flush()
    } catch {}
    if (-not $proc.WaitForExit(5000)) { $proc.Kill() }}
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
if (-not (Test-Path $serverJar)) { throw "Missing $serverJar. Run scripts/build-onyx.ps1 first." }
if (-not (Test-Path $serverConfigPath)) { throw "Missing $serverConfigPath. Run scripts/run-onyx.ps1 -InitOnly first." }
$server = $null
$client = $null
$originalServerConfig = $null
try {
    $originalServerConfig = Get-Content -Raw -Encoding UTF8 $serverConfigPath
    $serverConfig = $originalServerConfig
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^bind\s*=.*$' -line "bind = 127.0.0.1:$BackendPort"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^forwarding-mode\s*=.*$' -line "forwarding-mode = disabled"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-protocol-mode\s*=.*$' -line "play-protocol-mode = vanilla"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-enabled\s*=.*$' -line "play-session-enabled = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-duration-ms\s*=.*$' -line "play-session-duration-ms = 600"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-poll-timeout-ms\s*=.*$' -line "play-session-poll-timeout-ms = 50"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-max-packets\s*=.*$' -line "play-session-max-packets = 128"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-disconnect-on-limit\s*=.*$' -line "play-session-disconnect-on-limit = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-keepalive-enabled\s*=.*$' -line "play-keepalive-enabled = false"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-keepalive-clientbound-packet-id\s*=.*$' -line "play-keepalive-clientbound-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-keepalive-serverbound-packet-id\s*=.*$' -line "play-keepalive-serverbound-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-keepalive-interval-ms\s*=.*$' -line "play-keepalive-interval-ms = 100"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-keepalive-require-ack\s*=.*$' -line "play-keepalive-require-ack = false"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-keepalive-ack-timeout-ms\s*=.*$' -line "play-keepalive-ack-timeout-ms = 300"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-enabled\s*=.*$' -line "play-bootstrap-enabled = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-format\s*=.*$' -line "play-bootstrap-format = vanilla-minimal"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-init-packet-id\s*=.*$' -line "play-bootstrap-init-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-spawn-packet-id\s*=.*$' -line "play-bootstrap-spawn-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-message-packet-id\s*=.*$' -line "play-bootstrap-message-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-spawn-x\s*=.*$' -line "play-bootstrap-spawn-x = $SpawnX"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-spawn-y\s*=.*$' -line "play-bootstrap-spawn-y = $SpawnY"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-spawn-z\s*=.*$' -line "play-bootstrap-spawn-z = $SpawnZ"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-movement-enabled\s*=.*$' -line "play-movement-enabled = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-movement-teleport-id\s*=.*$' -line "play-movement-teleport-id = $ExpectedTeleportId"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-movement-teleport-confirm-packet-id\s*=.*$' -line "play-movement-teleport-confirm-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-movement-position-packet-id\s*=.*$' -line "play-movement-position-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-movement-rotation-packet-id\s*=.*$' -line "play-movement-rotation-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-movement-position-rotation-packet-id\s*=.*$' -line "play-movement-position-rotation-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-movement-on-ground-packet-id\s*=.*$' -line "play-movement-on-ground-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-movement-require-teleport-confirm\s*=.*$' -line "play-movement-require-teleport-confirm = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-movement-confirm-timeout-ms\s*=.*$' -line "play-movement-confirm-timeout-ms = 250"
    Set-Content -Path $serverConfigPath -Value $serverConfig -Encoding UTF8 -NoNewline
    $server = New-JavaProcess -fileName $JavaBinary -workingDir $serverDir -arguments "-jar onyxserver.jar --config onyxserver.conf --onyx-settings onyx.yml"
    Start-Sleep -Milliseconds 1200
    if ($server.HasExited) { throw "OnyxServer exited early. stderr: $($server.StandardError.ReadToEnd())" }
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
    if ($loginSuccess.Id -ne 0x02) { throw "Expected login success packet (0x02), got $($loginSuccess.Id)" }
    [void](Read-Exact $loginSuccess.Stream 16)
    [void](Read-McString $loginSuccess.Stream)
    [void](Read-VarInt $loginSuccess.Stream)
    $loginAck = Build-Packet { param($packetBody) Write-VarInt $packetBody $LoginAckPacketId }
    $stream.Write($loginAck, 0, $loginAck.Length)
    $configFinish = Read-Packet $stream
    if ($configFinish.Id -ne $ConfigFinishPacketId) { throw "Expected config finish packet ($ConfigFinishPacketId), got $($configFinish.Id)" }
    $clientFinish = Build-Packet { param($packetBody) Write-VarInt $packetBody $ConfigFinishPacketId }
    $stream.Write($clientFinish, 0, $clientFinish.Length)
    $sentConfirm = $false
    $sentRotation = $false
    $sentPositionRotation = $false
    $disconnectReason = ""
    $maxPackets = 128
    for ($i = 0; $i -lt $maxPackets; $i++) {
    
    $packet = Read-Packet $stream

    if ($packet.Id -eq $BootstrapInitPacketId) {
        continue
    }

    if ($packet.Id -eq $BootstrapMessagePacketId) {
        continue
    }
    
    if ($packet.Id -eq $BootstrapSpawnPacketId) {
        $teleportId = Read-VarInt $packet.Stream
        $spawnXRead = Read-DoubleBE $packet.Stream
        $spawnYRead = Read-DoubleBE $packet.Stream
        $spawnZRead = Read-DoubleBE $packet.Stream
        [void](Read-DoubleBE $packet.Stream) # delta X
        [void](Read-DoubleBE $packet.Stream) # delta Y
        [void](Read-DoubleBE $packet.Stream) # delta Z
        [void](Read-Exact $packet.Stream 8) # yaw + pitch
        $spawnFlags = Read-IntBE $packet.Stream
        if ($teleportId -ne $ExpectedTeleportId) {
            throw "Unexpected teleport id in spawn packet: $teleportId"
        }
        if ([math]::Abs($spawnXRead - $SpawnX) -gt 0.0001 -or [math]::Abs($spawnYRead - $SpawnY) -gt 0.0001 -or [math]::Abs($spawnZRead - $SpawnZ) -gt 0.0001) {
            throw "Unexpected spawn coordinates: $spawnXRead $spawnYRead $spawnZRead"
        }
        if ($spawnFlags -ne 0) {
            throw "Unexpected spawn flags bitfield: $spawnFlags"
        }
        $confirmPacket = Build-Packet {
            param($packetBody)
            Write-VarInt $packetBody $TeleportConfirmPacketId
            Write-VarInt $packetBody $teleportId
        }
        $stream.Write($confirmPacket, 0, $confirmPacket.Length)
        $sentConfirm = $true
        $rotationPacket = Build-Packet {
            param($packetBody)
            Write-VarInt $packetBody $RotationPacketId
            Write-FloatBE $packetBody ([single]12.5)
            Write-FloatBE $packetBody ([single]-5.25)
            $packetBody.WriteByte([byte]$MovementFlags)
        }
        $stream.Write($rotationPacket, 0, $rotationPacket.Length)
        $sentRotation = $true
        $positionRotationPacket = Build-Packet {
            param($packetBody)
            Write-VarInt $packetBody $PositionRotationPacketId
            Write-DoubleBE $packetBody $FinalX
            Write-DoubleBE $packetBody $FinalY
            Write-DoubleBE $packetBody $FinalZ
            Write-FloatBE $packetBody ([single]$FinalYaw)
            Write-FloatBE $packetBody ([single]$FinalPitch)
            $packetBody.WriteByte([byte]$MovementFlags)
        }
        $stream.Write($positionRotationPacket, 0, $positionRotationPacket.Length)
        $sentPositionRotation = $true
        continue
    
    }
    
    if ($packet.Id -eq $DisconnectPacketId) {
    
    
    $disconnectReason = Read-AnonymousNbtText $packet.Stream
    
    
    break
    
    }

    throw "Unexpected packet id during movement rotation vanilla flags run: $($packet.Id). Expected init=$BootstrapInitPacketId spawn=$BootstrapSpawnPacketId message=$BootstrapMessagePacketId disconnect=$DisconnectPacketId"
    }
    if (-not $sentConfirm) { throw "Teleport confirm packet was not sent" }
    if (-not $sentRotation) { throw "Rotation packet was not sent" }
    if (-not $sentPositionRotation) { throw "Position+rotation packet was not sent" }
    if ([string]::IsNullOrWhiteSpace($disconnectReason)) { throw "Did not receive final disconnect packet" }
    if ($disconnectReason -notmatch 'teleport-confirm=ok') { throw "Server did not report teleport confirm success: $disconnectReason" }
    if ($disconnectReason -notmatch 'movement-packets=2') { throw "Server did not record total movement packets: $disconnectReason" }
    if ($disconnectReason -notmatch 'movement-rotation-packets=1') { throw "Server did not record rotation packet: $disconnectReason" }
    if ($disconnectReason -notmatch 'movement-position-rotation-packets=1') { throw "Server did not record position+rotation packet: $disconnectReason" }
    if ($disconnectReason -notmatch 'movement-on-ground-packets=0') { throw "Unexpected on-ground packet count: $disconnectReason" }
    if ($disconnectReason -notmatch 'movement-last=5\.500/71\.250/3\.000') { throw "Server did not report expected final coordinates: $disconnectReason" }
    if ($disconnectReason -notmatch 'movement-last-rot=179\.750/2\.500') { throw "Server did not report expected final rotation: $disconnectReason" }
    if ($disconnectReason -notmatch 'on-ground=false') { throw "Server did not report final on-ground state: $disconnectReason" }
    Write-Host "[ONYX] E2E_PLAY_MOVEMENT_ROTATION_VANILLA_FLAGS_OK"
    Write-Host "[ONYX] DISCONNECT_REASON=$disconnectReason"
} finally {
    if ($client -ne $null) { $client.Close() }
    Stop-JavaProcess -proc $server -stopCommand "stop"
    if ($null -ne $originalServerConfig) {
    
    Set-Content -Path $serverConfigPath -Value $originalServerConfig -Encoding UTF8 -NoNewline
    }}
