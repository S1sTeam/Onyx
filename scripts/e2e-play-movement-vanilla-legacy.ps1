param(
    [string]$JavaBinary = "java",
    [string]$DistPath = "dist",
    [int]$BackendPort = 35566 )
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$Protocol = 47
$DisconnectPacketId = 0x40
$BootstrapInitPacketId = 0x01
$BootstrapSpawnPacketId = 0x08
$BootstrapMessagePacketId = 0x02
$PositionPacketId = 0x04
$RotationPacketId = 0x05
$PositionRotationPacketId = 0x06
$OnGroundPacketId = 0x03
$ExpectedUsername = "MoveLegacyProbe"
$SpawnX = 2.0
$SpawnY = 70.0
$SpawnZ = 2.0
$MoveX = 2.25
$MoveY = 70.0
$MoveZ = -1.25
$RotYaw = 12.5
$RotPitch = -5.25
$FinalX = 5.5
$FinalY = 71.25
$FinalZ = 3.0
$FinalYaw = 179.75
$FinalPitch = 2.5
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
function Read-FloatBE([System.IO.Stream]$stream) {
    $bytes = Read-Exact $stream 4
    [Array]::Reverse($bytes)
    return [System.BitConverter]::ToSingle($bytes, 0)}
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
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-duration-ms\s*=.*$' -line "play-session-duration-ms = 900"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-poll-timeout-ms\s*=.*$' -line "play-session-poll-timeout-ms = 50"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-max-packets\s*=.*$' -line "play-session-max-packets = 128"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-disconnect-on-limit\s*=.*$' -line "play-session-disconnect-on-limit = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-enabled\s*=.*$' -line "play-bootstrap-enabled = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-format\s*=.*$' -line "play-bootstrap-format = vanilla-minimal"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-init-packet-id\s*=.*$' -line "play-bootstrap-init-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-spawn-packet-id\s*=.*$' -line "play-bootstrap-spawn-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-message-packet-id\s*=.*$' -line "play-bootstrap-message-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-spawn-x\s*=.*$' -line "play-bootstrap-spawn-x = $SpawnX"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-spawn-y\s*=.*$' -line "play-bootstrap-spawn-y = $SpawnY"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-spawn-z\s*=.*$' -line "play-bootstrap-spawn-z = $SpawnZ"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-movement-enabled\s*=.*$' -line "play-movement-enabled = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-movement-teleport-id\s*=.*$' -line "play-movement-teleport-id = 77"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-movement-teleport-confirm-packet-id\s*=.*$' -line "play-movement-teleport-confirm-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-movement-position-packet-id\s*=.*$' -line "play-movement-position-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-movement-rotation-packet-id\s*=.*$' -line "play-movement-rotation-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-movement-position-rotation-packet-id\s*=.*$' -line "play-movement-position-rotation-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-movement-on-ground-packet-id\s*=.*$' -line "play-movement-on-ground-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-movement-require-teleport-confirm\s*=.*$' -line "play-movement-require-teleport-confirm = false"
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
    }
    $stream.Write($handshake, 0, $handshake.Length)
    $stream.Write($loginStart, 0, $loginStart.Length)
    $loginSuccess = Read-Packet $stream
    if ($loginSuccess.Id -ne 0x02) { throw "Expected login success packet (0x02), got $($loginSuccess.Id)" }
    [void](Read-McString $loginSuccess.Stream) # UUID string
    $loginUser = Read-McString $loginSuccess.Stream
    if ($loginUser -ne $ExpectedUsername) { throw "Unexpected username in login success: $loginUser" }
    $gotInit = $false
    $gotSpawn = $false
    $gotMessage = $false
    $sentPosition = $false
    $sentRotation = $false
    $sentPositionRotation = $false
    $sentOnGround = $false
    $disconnectReason = ""
    $maxPackets = 128
    for ($i = 0; $i -lt $maxPackets; $i++) {
    
    $packet = Read-Packet $stream
    
    if ($packet.Id -eq $BootstrapInitPacketId) {
        $entityId = Read-IntBE $packet.Stream
        $gameMode = $packet.Stream.ReadByte()
        $dimension = $packet.Stream.ReadByte()
        $difficulty = $packet.Stream.ReadByte()
        $maxPlayers = $packet.Stream.ReadByte()
        $levelType = Read-McString $packet.Stream
        $reducedDebug = $packet.Stream.ReadByte()
        if ($entityId -ne 1 -or $gameMode -ne 0 -or $dimension -ne 0 -or $difficulty -ne 1) {
            throw "Unexpected legacy init payload"
        }
        if ($maxPlayers -lt 1 -or $levelType -ne "default" -or $reducedDebug -ne 0) {
            throw "Unexpected legacy init metadata"
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
        if ([math]::Abs($x - $SpawnX) -gt 0.0001 -or [math]::Abs($y - $SpawnY) -gt 0.0001 -or [math]::Abs($z - $SpawnZ) -gt 0.0001) {
            throw "Unexpected legacy spawn coordinates: $x $y $z"
        }
        if ([math]::Abs($yaw) -gt 0.0001 -or [math]::Abs($pitch) -gt 0.0001 -or $flags -ne 0) {
            throw "Unexpected legacy spawn orientation payload"
        }
        $gotSpawn = $true

        $positionPacket = Build-Packet {
            param($packetBody)
            Write-VarInt $packetBody $PositionPacketId
            Write-DoubleBE $packetBody $MoveX
            Write-DoubleBE $packetBody $MoveY
            Write-DoubleBE $packetBody $MoveZ
            $packetBody.WriteByte(1)
        }
        $stream.Write($positionPacket, 0, $positionPacket.Length)
        $sentPosition = $true

        $rotationPacket = Build-Packet {
            param($packetBody)
            Write-VarInt $packetBody $RotationPacketId
            Write-FloatBE $packetBody ([single]$RotYaw)
            Write-FloatBE $packetBody ([single]$RotPitch)
            $packetBody.WriteByte(1)
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
            $packetBody.WriteByte(1)
        }
        $stream.Write($positionRotationPacket, 0, $positionRotationPacket.Length)
        $sentPositionRotation = $true

        $onGroundPacket = Build-Packet {
            param($packetBody)
            Write-VarInt $packetBody $OnGroundPacketId
            $packetBody.WriteByte(0)
        }
        $stream.Write($onGroundPacket, 0, $onGroundPacket.Length)
        $sentOnGround = $true
        continue
    }

    if ($packet.Id -eq $BootstrapMessagePacketId) {
        $jsonMessage = Read-McString $packet.Stream
        $position = $packet.Stream.ReadByte()
        if ($position -lt 0) {
            throw "Unexpected EOF while reading legacy chat position"
        }
        if ($position -ne 1 -or $jsonMessage -notmatch "Onyx") {
            throw "Unexpected legacy bootstrap message payload"
        }
        $gotMessage = $true
        continue
    }

    if ($packet.Id -eq $DisconnectPacketId) {
        $disconnectReason = Read-McString $packet.Stream
        break
    }
    }
    if (-not $gotInit) { throw "Legacy vanilla bootstrap init packet not received" }
    if (-not $gotSpawn) { throw "Legacy vanilla bootstrap spawn packet not received" }
    if (-not $gotMessage) { throw "Legacy vanilla bootstrap message packet not received" }
    if (-not $sentPosition) { throw "Legacy position packet was not sent" }
    if (-not $sentRotation) { throw "Rotation packet was not sent" }
    if (-not $sentPositionRotation) { throw "Position+rotation packet was not sent" }
    if (-not $sentOnGround) { throw "Legacy on-ground packet was not sent" }
    if ([string]::IsNullOrWhiteSpace($disconnectReason)) { throw "Did not receive final disconnect packet" }
    if ($disconnectReason -notmatch 'movement-packets=4') { throw "Server did not record total movement packets: $disconnectReason" }
    if ($disconnectReason -notmatch 'movement-position-packets=1') { throw "Server did not record position packet: $disconnectReason" }
    if ($disconnectReason -notmatch 'movement-rotation-packets=1') { throw "Server did not record rotation packet: $disconnectReason" }
    if ($disconnectReason -notmatch 'movement-position-rotation-packets=1') { throw "Server did not record position+rotation packet: $disconnectReason" }
    if ($disconnectReason -notmatch 'movement-on-ground-packets=1') { throw "Server did not record on-ground packet: $disconnectReason" }
    if ($disconnectReason -notmatch 'movement-last=5\.500/71\.250/3\.000') { throw "Server did not report expected final coordinates: $disconnectReason" }
    if ($disconnectReason -notmatch 'movement-last-rot=179\.750/2\.500') { throw "Server did not report expected final rotation: $disconnectReason" }
    if ($disconnectReason -notmatch 'on-ground=false') { throw "Server did not report final on-ground state: $disconnectReason" }
    Write-Host "[ONYX] E2E_PLAY_MOVEMENT_VANILLA_LEGACY_OK"
    Write-Host "[ONYX] DISCONNECT_REASON=$disconnectReason"
} finally {
    if ($client -ne $null) { $client.Close() }
    Stop-JavaProcess -proc $server -stopCommand "stop"
    if ($null -ne $originalServerConfig) {
    
    Set-Content -Path $serverConfigPath -Value $originalServerConfig -Encoding UTF8 -NoNewline
    }}
