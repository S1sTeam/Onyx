param(
    [string]$JavaBinary = "java",
    [string]$DistPath = "dist",
    [int]$ProxyPort = 26565,
    [int]$BackendPort = 26566 )
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$PlayDisconnectIdByProtocol = [ordered]@{
    47  = 0x40
    107 = 0x1A
    393 = 0x1B
    477 = 0x1A
    573 = 0x1B
    735 = 0x1A
    751 = 0x19
    755 = 0x1A
    759 = 0x17
    760 = 0x19
    761 = 0x17
    762 = 0x1A
    764 = 0x1B
    766 = 0x1D
    770 = 0x1C
    773 = 0x20}
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
    [PSCustomObject]@{
    
    Id = $packetId
    
    Stream = $packetMem
    }}
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
function Read-NbtString([System.IO.Stream]$stream) {
    $len = Read-UShortBE $stream
    $bytes = Read-Exact $stream $len
    return [System.Text.Encoding]::UTF8.GetString($bytes)}
function Read-AnonymousNbtText([System.IO.Stream]$stream) {
    $tagType = $stream.ReadByte()
    if ($tagType -ne 0x0A) {
    
    throw "Expected TAG_Compound root for anonymous NBT, got $tagType"
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
    
    
    throw "Unsupported NBT entry type in test parser: $entryType"
    
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
function Get-PlayDisconnectId([int]$protocol) {
    $selected = 0x40
    foreach ($entry in $PlayDisconnectIdByProtocol.GetEnumerator()) {
    
    if ($protocol -ge [int]$entry.Key) {
    
    
    $selected = [int]$entry.Value
    
    } else {
    
    
    break
    
    }
    }
    return $selected}
function Get-ConfigurationFinishPacketId([int]$protocol) {
    if ($protocol -ge 766) {
    
    return 0x03
    }
    return 0x02}
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
function Upsert-Line([string]$content, [string]$pattern, [string]$line) {
    if ($content -match $pattern) {
    
    return [System.Text.RegularExpressions.Regex]::Replace($content, $pattern, $line)
    }
    if ($content.Length -gt 0 -and -not $content.EndsWith("`n")) {
    
    $content += "`n"
    }
    return $content + $line}
function Write-LoginStartPayload([System.IO.Stream]$packetBody, [int]$protocol, [string]$username, [byte[]]$uuidBytes) {
    Write-VarInt $packetBody 0x00
    Write-McString $packetBody $username
    if ($protocol -ge 764) {
    
    $packetBody.Write($uuidBytes, 0, $uuidBytes.Length)
    
    return
    }
    if ($protocol -ge 761) {
    
    $packetBody.WriteByte(0) # optional UUID absent
    
    return
    }
    if ($protocol -eq 760) {
    
    $packetBody.WriteByte(0) # optional signature absent
    
    $packetBody.WriteByte(0) # optional UUID absent
    
    return
    }
    if ($protocol -eq 759) {
    
    $packetBody.WriteByte(0) # optional signature absent
    }}
function Read-LoginSuccessPacket([System.IO.Stream]$stream, [int]$protocol) {
    $packet = Read-Packet $stream
    if ($packet.Id -ne 0x02) {
    
    throw "Expected login success packet (0x02), got $($packet.Id) for protocol $protocol"
    }
    $uuidText = ""
    if ($protocol -ge 735) {
    
    $uuidBytes = Read-Exact $packet.Stream 16
    
    $uuidText = [BitConverter]::ToString($uuidBytes).Replace("-", "")
    } else {
    
    $uuidText = Read-McString $packet.Stream
    }
    $username = Read-McString $packet.Stream
    if ($protocol -ge 759) {
    
    $propertyCount = Read-VarInt $packet.Stream
    
    for ($i = 0; $i -lt $propertyCount; $i++) {
    
    
    [void](Read-McString $packet.Stream)
    
    
    [void](Read-McString $packet.Stream)
    
    
    $hasSig = $packet.Stream.ReadByte()
    
    
    if ($hasSig -lt 0) {
    
    
    
    throw "Unexpected EOF in property signature flag for protocol $protocol"
    
    
    }
    
    
    if ($hasSig -ne 0) {
    
    
    
    [void](Read-McString $packet.Stream)
    
    
    }
    
    }
    }
    if ($protocol -eq 766) {
    
    $strictFlag = $packet.Stream.ReadByte()
    
    if ($strictFlag -lt 0) {
    
    
    throw "Missing strict error handling flag for protocol 766"
    
    }
    }
    return [PSCustomObject]@{
    
    Username = $username
    
    UuidText = $uuidText
    }}
function Read-PlayDisconnectPacket([System.IO.Stream]$stream, [int]$protocol) {
    $expectedId = Get-PlayDisconnectId -protocol $protocol
    $maxPackets = 64
    for ($i = 0; $i -lt $maxPackets; $i++) {
    
    $packet = Read-Packet $stream
    
    if ($packet.Id -ne $expectedId) {
    
    
    continue
    
    }
    
    if ($protocol -ge 766) {
    
    
    $reason = Read-AnonymousNbtText $packet.Stream
    
    } else {
    
    
    $reason = Read-McString $packet.Stream
    
    }
    
    if ([string]::IsNullOrWhiteSpace($reason) -or $reason -notmatch 'Onyx play session ended') {
    
    
    throw "Unexpected disconnect reason for protocol ${protocol}: $reason"
    
    }
    
    if ($reason -notmatch 'stage:') {
    
    
    throw "Missing play-stage marker in disconnect reason for protocol ${protocol}: $reason"
    
    }
    
    if ($reason -notmatch 'packets=\d+') {
    
    
    throw "Missing packet counter in disconnect reason for protocol ${protocol}: $reason"
    
    }
    
    return $reason
    }
    throw "Did not receive play disconnect packet ($expectedId) for protocol $protocol within $maxPackets packets"}
function Invoke-LoginCase([int]$protocol, [int]$port, [string]$username, [byte[]]$uuidBytes) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
    
    $client.Connect("127.0.0.1", $port)
    
    $stream = $client.GetStream()
    
    $handshake = Build-Packet {
    
    
    param($packetBody)
    
    
    Write-VarInt $packetBody 0x00
    
    
    Write-VarInt $packetBody $protocol
    
    
    Write-McString $packetBody "127.0.0.1"
    
    
    Write-UShortBE $packetBody $port
    
    
    Write-VarInt $packetBody 0x02
    
    }
    
    $loginStart = Build-Packet {
    
    
    param($packetBody)
    
    
    Write-LoginStartPayload -packetBody $packetBody -protocol $protocol -username $username -uuidBytes $uuidBytes
    
    }
    
    $stream.Write($handshake, 0, $handshake.Length)
    
    $stream.Write($loginStart, 0, $loginStart.Length)
    
    $loginSuccess = Read-LoginSuccessPacket -stream $stream -protocol $protocol
    
    if ($loginSuccess.Username -ne $username) {
    
    
    throw "Unexpected username in login success for protocol ${protocol}: $($loginSuccess.Username)"
    
    }
    
    if ($protocol -ge 764) {
    
    
    $loginAck = Build-Packet {
    
    
    
    param($packetBody)
    
    
    
    Write-VarInt $packetBody 0x03
    
    
    }
    
    
    $stream.Write($loginAck, 0, $loginAck.Length)
    
    
    $expectedConfigFinishId = Get-ConfigurationFinishPacketId -protocol $protocol
    
    
    $configFinish = Read-Packet $stream
    
    
    if ($configFinish.Id -ne $expectedConfigFinishId) {
    
    
    
    throw "Expected configuration finish packet ($expectedConfigFinishId), got $($configFinish.Id) for protocol $protocol"
    
    
    }
    
    
    $clientFinish = Build-Packet {
    
    
    
    param($packetBody)
    
    
    
    Write-VarInt $packetBody $expectedConfigFinishId
    
    
    }
    
    
    $stream.Write($clientFinish, 0, $clientFinish.Length)
    
    }
    
    $playProbe = Build-Packet {
    
    
    param($packetBody)
    
    
    Write-VarInt $packetBody 0x00
    
    }
    
    $stream.Write($playProbe, 0, $playProbe.Length)
    
    $reason = Read-PlayDisconnectPacket -stream $stream -protocol $protocol
    
    Write-Host "[ONYX] LOGIN_CASE_OK protocol=$protocol user=$username"
    
    Write-Host "[ONYX] LOGIN_CASE_DISCONNECT protocol=$protocol reason=$reason"
    } finally {
    
    $client.Close()
    }}
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$dist = Join-Path $root $DistPath
$serverDir = Join-Path $dist "runtime/onyxserver"
$proxyDir = Join-Path $dist "runtime/onyxproxy"
$serverJar = Join-Path $serverDir "onyxserver.jar"
$proxyJar = Join-Path $proxyDir "onyxproxy.jar"
if (-not (Test-Path $serverJar)) {
    throw "Missing $serverJar. Run scripts/build-onyx.ps1 first."
}
if (-not (Test-Path $proxyJar)) {
    throw "Missing $proxyJar. Run scripts/build-onyx.ps1 first."}
$server = $null
$proxy = $null
$serverConfigPath = Join-Path $serverDir "onyxserver.conf"
$proxyConfigPath = Join-Path $proxyDir "onyxproxy.conf"
$originalServerConfig = $null
$originalProxyConfig = $null
try {
    if (-not (Test-Path $serverConfigPath)) {
    
    $serverDefaults = @(
    
    
    "# OnyxServer native config",
    
    
    "version = 1",
    
    
    "bind = 127.0.0.1:25566",
    
    
    "motd = Onyx Local Server",
    
    
    "max-players = 500",
    
    
    "status-version-name = Onyx Native",
    
    
    "status-protocol-version = -1",
    
    
    "forwarding-mode = disabled",
    
    
    "forwarding-max-age-seconds = 30"
    
    )
    
    Set-Content -Path $serverConfigPath -Value $serverDefaults -Encoding UTF8
    }
    if (-not (Test-Path $proxyConfigPath)) {
    
    $proxyDefaults = @(
    
    
    "# OnyxProxy native config",
    
    
    "version = 1",
    
    
    "bind = 0.0.0.0:25565",
    
    
    "backend = 127.0.0.1:25566",
    
    
    "motd = OnyxProxy Native"
    
    )
    
    Set-Content -Path $proxyConfigPath -Value $proxyDefaults -Encoding UTF8
    }
    $originalServerConfig = Get-Content -Raw -Encoding UTF8 $serverConfigPath
    $serverConfig = [System.Text.RegularExpressions.Regex]::Replace($originalServerConfig, '(?m)^bind\s*=.*$', "bind = 127.0.0.1:$BackendPort")
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^forwarding-mode\s*=.*$' -line "forwarding-mode = disabled"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-enabled\s*=.*$' -line "play-session-enabled = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-duration-ms\s*=.*$' -line "play-session-duration-ms = 250"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-poll-timeout-ms\s*=.*$' -line "play-session-poll-timeout-ms = 50"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-max-packets\s*=.*$' -line "play-session-max-packets = 128"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-disconnect-on-limit\s*=.*$' -line "play-session-disconnect-on-limit = true"
    Set-Content -Path $serverConfigPath -Value $serverConfig -Encoding UTF8 -NoNewline
    $originalProxyConfig = Get-Content -Raw -Encoding UTF8 $proxyConfigPath
    $proxyConfig = [System.Text.RegularExpressions.Regex]::Replace($originalProxyConfig, '(?m)^bind\s*=.*$', "bind = 127.0.0.1:$ProxyPort")
    $proxyConfig = [System.Text.RegularExpressions.Regex]::Replace($proxyConfig, '(?m)^backend\s*=.*$', "backend = 127.0.0.1:$BackendPort")
    $proxyConfig = Upsert-Line -content $proxyConfig -pattern '(?m)^forwarding-mode\s*=.*$' -line "forwarding-mode = disabled"
    $proxyConfig = [System.Text.RegularExpressions.Regex]::Replace($proxyConfig, '(?m)^server\.[A-Za-z0-9_.-]+\s*=.*$', "server.local = 127.0.0.1:$BackendPort")
    if ($proxyConfig -notmatch '(?m)^server\.local\s*=') {
    
    $proxyConfig += "`nserver.local = 127.0.0.1:$BackendPort"
    }
    Set-Content -Path $proxyConfigPath -Value $proxyConfig -Encoding UTF8 -NoNewline
    $server = New-JavaProcess -fileName $JavaBinary -workingDir $serverDir -arguments "-jar onyxserver.jar --config onyxserver.conf --onyx-settings onyx.yml"
    Start-Sleep -Milliseconds 1200
    if ($server.HasExited) {
    
    throw "OnyxServer exited early with code $($server.ExitCode). stderr: $($server.StandardError.ReadToEnd())"
    }
    $proxy = New-JavaProcess -fileName $JavaBinary -workingDir $proxyDir -arguments "-Donyxproxy.config=onyxproxy.conf -jar onyxproxy.jar"
    Start-Sleep -Milliseconds 1200
    if ($proxy.HasExited) {
    
    throw "OnyxProxy exited early with code $($proxy.ExitCode). stderr: $($proxy.StandardError.ReadToEnd())"
    }
    Wait-TcpPort -hostName "127.0.0.1" -port $ProxyPort -timeoutMs 8000
    $testProtocols = @(47, 340, 758, 759, 760, 763, 764, 765, 766, 769, 770, 773, 774, 775)
    $uuidBytes = Convert-GuidToNetworkBytes -guid ([Guid]::Parse("00112233-4455-6677-8899-aabbccddeeff"))
    foreach ($protocol in $testProtocols) {
    
    $username = "P$protocol"
    
    if ($username.Length -gt 16) {
    
    
    $username = $username.Substring(0, 16)
    
    }
    
    Invoke-LoginCase -protocol $protocol -port $ProxyPort -username $username -uuidBytes $uuidBytes
    }
    Write-Host "[ONYX] E2E_LOGIN_OK"
} finally {
    Stop-JavaProcess -proc $proxy -stopCommand "shutdown"
    Stop-JavaProcess -proc $server -stopCommand "stop"
    if ($null -ne $originalServerConfig) {
    
    Set-Content -Path $serverConfigPath -Value $originalServerConfig -Encoding UTF8 -NoNewline
    }
    if ($null -ne $originalProxyConfig) {
    
    Set-Content -Path $proxyConfigPath -Value $originalProxyConfig -Encoding UTF8 -NoNewline
    }
}