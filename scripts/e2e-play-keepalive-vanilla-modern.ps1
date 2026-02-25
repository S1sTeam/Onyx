param(
    [string]$JavaBinary = "java",
    [string]$DistPath = "dist",
    [int]$BackendPort = 36566,
    [int]$Protocol = 769,
    [int]$DisconnectPacketId = 0x1D,
    [int]$LoginAckPacketId = 0x03,
    [int]$ConfigFinishPacketId = 0x03,
    [int]$KeepAliveClientboundId = 0x27,
    [int]$KeepAliveServerboundId = 0x1A,
    [string]$ExpectedUsername = "KeepAliveModern",
    [switch]$UseAutoPacketIds
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
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
function Write-LongBE([System.IO.Stream]$stream, [Int64]$value) {
    $bytes = [System.BitConverter]::GetBytes([Int64]$value)
    [Array]::Reverse($bytes)
    $stream.Write($bytes, 0, $bytes.Length)}
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
    $keepaliveClientboundConfigId = if ($UseAutoPacketIds) { -1 } else { $KeepAliveClientboundId }
    $keepaliveServerboundConfigId = if ($UseAutoPacketIds) { -1 } else { $KeepAliveServerboundId }
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^bind\s*=.*$' -line "bind = 127.0.0.1:$BackendPort"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^forwarding-mode\s*=.*$' -line "forwarding-mode = disabled"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-protocol-mode\s*=.*$' -line "play-protocol-mode = vanilla"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-enabled\s*=.*$' -line "play-session-enabled = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-duration-ms\s*=.*$' -line "play-session-duration-ms = 600"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-poll-timeout-ms\s*=.*$' -line "play-session-poll-timeout-ms = 50"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-max-packets\s*=.*$' -line "play-session-max-packets = 256"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-disconnect-on-limit\s*=.*$' -line "play-session-disconnect-on-limit = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-enabled\s*=.*$' -line "play-bootstrap-enabled = false"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-movement-enabled\s*=.*$' -line "play-movement-enabled = false"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-keepalive-enabled\s*=.*$' -line "play-keepalive-enabled = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-keepalive-clientbound-packet-id\s*=.*$' -line "play-keepalive-clientbound-packet-id = $keepaliveClientboundConfigId"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-keepalive-serverbound-packet-id\s*=.*$' -line "play-keepalive-serverbound-packet-id = $keepaliveServerboundConfigId"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-keepalive-interval-ms\s*=.*$' -line "play-keepalive-interval-ms = 80"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-keepalive-require-ack\s*=.*$' -line "play-keepalive-require-ack = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-keepalive-ack-timeout-ms\s*=.*$' -line "play-keepalive-ack-timeout-ms = 350"
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
    $acked = 0
    $disconnectReason = ""
    $maxPackets = 128
    for ($i = 0; $i -lt $maxPackets; $i++) {
    
    $packet = Read-Packet $stream
    
    if ($packet.Id -eq $KeepAliveClientboundId) {
        $token = Read-LongBE $packet.Stream
        $ackPacket = Build-Packet {
            param($packetBody)
            Write-VarInt $packetBody $KeepAliveServerboundId
            Write-LongBE $packetBody $token
        }
        $stream.Write($ackPacket, 0, $ackPacket.Length)
        $acked++
        continue
    
    }
    
    if ($packet.Id -eq $DisconnectPacketId) {
    
    
    $disconnectReason = Read-AnonymousNbtText $packet.Stream
    
    
    break
    
    }

    throw "Unexpected packet id during keepalive run: $($packet.Id). Expected keepalive=$KeepAliveClientboundId or disconnect=$DisconnectPacketId"
    }
    if ($acked -lt 1) {
    
    throw "Did not receive keepalive packets from server"
    }
    if ([string]::IsNullOrWhiteSpace($disconnectReason)) {
    
    throw "Did not receive final disconnect packet"
    }
    if ($disconnectReason -notmatch 'keepalive-sent=') {
    
    throw "Disconnect reason does not include keepalive metrics: $disconnectReason"
    }
    if ($disconnectReason -notmatch 'keepalive-acked=') {
    
    throw "Disconnect reason does not include keepalive ack metrics: $disconnectReason"
    }
    $ackMatch = [System.Text.RegularExpressions.Regex]::Match($disconnectReason, 'keepalive-acked=(\d+)')
    if (-not $ackMatch.Success) {
    
    throw "Unable to parse keepalive ack metric from reason: $disconnectReason"
    }
    $ackedByServer = [int]$ackMatch.Groups[1].Value
    if ($ackedByServer -lt 1) {
    
    throw "Server reported zero keepalive acks: $disconnectReason"
    }
    Write-Host "[ONYX] E2E_PLAY_KEEPALIVE_VANILLA_MODERN_OK"
    Write-Host "[ONYX] KEEPALIVE_CLIENT_ACKED=$acked"
    Write-Host "[ONYX] DISCONNECT_REASON=$disconnectReason"
} finally {
    if ($client -ne $null) {
    
    $client.Close()
    }
    Stop-JavaProcess -proc $server -stopCommand "stop"
    if ($null -ne $originalServerConfig) {
    
    Set-Content -Path $serverConfigPath -Value $originalServerConfig -Encoding UTF8 -NoNewline
    }}
