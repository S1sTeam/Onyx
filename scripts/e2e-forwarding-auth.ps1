param(
    [string]$JavaBinary = "java",
    [string]$DistPath = "dist",
    [int]$ProxyPort = 29565,
    [int]$BackendPort = 29566,
    [int]$Protocol = 769 )
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$PlayDisconnectId = 0x1D
$ConfigFinishId = 0x03
$ForwardingSecret = "onyx-e2e-forwarding-secret"
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
function Read-LoginSuccess769([System.IO.Stream]$stream, [string]$expectedUsername) {
    $packet = Read-Packet $stream
    if ($packet.Id -ne 0x02) {
    
    throw "Expected login success packet (0x02), got $($packet.Id)"
    }
    [void](Read-Exact $packet.Stream 16) # UUID bytes
    $username = Read-McString $packet.Stream
    if ($username -ne $expectedUsername) {
    
    throw "Unexpected username in login success: $username"
    }
    $propertyCount = Read-VarInt $packet.Stream
    for ($i = 0; $i -lt $propertyCount; $i++) {
    
    [void](Read-McString $packet.Stream)
    
    [void](Read-McString $packet.Stream)
    
    $hasSig = $packet.Stream.ReadByte()
    
    if ($hasSig -lt 0) {
    
    
    throw "Unexpected EOF in property signature flag"
    
    }
    
    if ($hasSig -ne 0) {
    
    
    [void](Read-McString $packet.Stream)
    
    }
    }}
function Invoke-ProxiedLogin([int]$port, [string]$username, [byte[]]$uuidBytes) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
    
    $client.Connect("127.0.0.1", $port)
    
    $stream = $client.GetStream()
    
    $stream.ReadTimeout = 5000
    
    $handshake = Build-Packet {
    
    
    param($packetBody)
    
    
    Write-VarInt $packetBody 0x00
    
    
    Write-VarInt $packetBody $Protocol
    
    
    Write-McString $packetBody "secured.local"
    
    
    Write-UShortBE $packetBody $port
    
    
    Write-VarInt $packetBody 0x02
    
    }
    
    $loginStart = Build-Packet {
    
    
    param($packetBody)
    
    
    Write-VarInt $packetBody 0x00
    
    
    Write-McString $packetBody $username
    
    
    $packetBody.Write($uuidBytes, 0, $uuidBytes.Length)
    
    }
    
    $stream.Write($handshake, 0, $handshake.Length)
    
    $stream.Write($loginStart, 0, $loginStart.Length)
    
    Read-LoginSuccess769 -stream $stream -expectedUsername $username
    
    $loginAck = Build-Packet {
    
    
    param($packetBody)
    
    
    Write-VarInt $packetBody 0x03
    
    }
    
    $stream.Write($loginAck, 0, $loginAck.Length)
    
    $configFinish = Read-Packet $stream
    
    if ($configFinish.Id -ne $ConfigFinishId) {
    
    
    throw "Expected config finish packet ($ConfigFinishId), got $($configFinish.Id)"
    
    }
    
    $clientFinish = Build-Packet {
    
    
    param($packetBody)
    
    
    Write-VarInt $packetBody $ConfigFinishId
    
    }
    
    $stream.Write($clientFinish, 0, $clientFinish.Length)
    
    $reason = $null
    
    $maxPackets = 64
    
    for ($i = 0; $i -lt $maxPackets; $i++) {
    
    
    $disconnect = Read-Packet $stream
    
    
    if ($disconnect.Id -ne $PlayDisconnectId) {
    
    
    
    continue
    
    
    }
    
    
    $reason = Read-AnonymousNbtText $disconnect.Stream
    
    
    break
    
    }
    
    if ([string]::IsNullOrWhiteSpace($reason)) {
    
    
    throw "Did not receive play disconnect packet ($PlayDisconnectId)"
    
    }
    
    if ([string]::IsNullOrWhiteSpace($reason) -or $reason -notmatch "Onyx play session ended") {
    
    
    throw "Unexpected proxied disconnect reason: $reason"
    
    }
    
    return $reason
    } finally {
    
    $client.Close()
    }}
function Invoke-DirectLoginExpectBlocked([int]$port, [string]$username, [byte[]]$uuidBytes) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
    
    $client.Connect("127.0.0.1", $port)
    
    $stream = $client.GetStream()
    
    $stream.ReadTimeout = 4000
    
    $handshake = Build-Packet {
    
    
    param($packetBody)
    
    
    Write-VarInt $packetBody 0x00
    
    
    Write-VarInt $packetBody $Protocol
    
    
    Write-McString $packetBody "secured.local"
    
    
    Write-UShortBE $packetBody $port
    
    
    Write-VarInt $packetBody 0x02
    
    }
    
    $loginStart = Build-Packet {
    
    
    param($packetBody)
    
    
    Write-VarInt $packetBody 0x00
    
    
    Write-McString $packetBody $username
    
    
    $packetBody.Write($uuidBytes, 0, $uuidBytes.Length)
    
    }
    
    $stream.Write($handshake, 0, $handshake.Length)
    
    $stream.Write($loginStart, 0, $loginStart.Length)
    
    try {
    
    
    $packet = Read-Packet $stream
    
    } catch {
    
    
    if ($_.Exception.Message -match "EOF") {
    
    
    
    return "connection_closed"
    
    
    }
    
    
    throw
    
    }
    
    if ($packet.Id -eq 0x02) {
    
    
    throw "Direct backend login unexpectedly succeeded"
    
    }
    
    if ($packet.Id -eq 0x00) {
    
    
    $reason = Read-McString $packet.Stream
    
    
    if ($reason -notmatch "forwarding") {
    
    
    
    throw "Direct login rejected but reason is unexpected: $reason"
    
    
    }
    
    
    return $reason
    
    }
    
    return "packet_id_$($packet.Id)"
    } finally {
    
    $client.Close()
    }}
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$dist = Join-Path $root $DistPath
$serverDir = Join-Path $dist "runtime/onyxserver"
$proxyDir = Join-Path $dist "runtime/onyxproxy"
$serverJar = Join-Path $serverDir "onyxserver.jar"
$proxyJar = Join-Path $proxyDir "onyxproxy.jar"
$serverConfigPath = Join-Path $serverDir "onyxserver.conf"
$proxyConfigPath = Join-Path $proxyDir "onyxproxy.conf"
$proxySecretPath = Join-Path $proxyDir "forwarding.secret"
if (-not (Test-Path $serverJar)) {
    throw "Missing $serverJar. Run scripts/build-onyx.ps1 first."
}
if (-not (Test-Path $proxyJar)) {
    throw "Missing $proxyJar. Run scripts/build-onyx.ps1 first."}
$server = $null
$proxy = $null
$originalServerConfig = $null
$originalProxyConfig = $null
$originalProxySecret = $null
$hadProxySecret = $false
$serverStdErr = ""
$serverStdOut = ""
$proxyStdErr = ""
$proxyStdOut = ""
$succeeded = $false
try {
    if (-not (Test-Path $serverConfigPath)) {
    
    Set-Content -Path $serverConfigPath -Value @(
    
    
    "# OnyxServer native config",
    
    
    "version = 1",
    
    
    "bind = 127.0.0.1:25566",
    
    
    "motd = Onyx Local Server",
    
    
    "max-players = 500",
    
    
    "status-version-name = Onyx Native",
    
    
    "status-protocol-version = -1",
    
    
    "forwarding-mode = disabled",
    
    
    "forwarding-max-age-seconds = 30"
    
    ) -Encoding UTF8
    }
    if (-not (Test-Path $proxyConfigPath)) {
    
    Set-Content -Path $proxyConfigPath -Value @(
    
    
    "# OnyxProxy native config",
    
    
    "version = 1",
    
    
    "bind = 0.0.0.0:25565",
    
    
    "backend = 127.0.0.1:25566",
    
    
    "server.local = 127.0.0.1:25566",
    
    
    "try = local",
    
    
    "forwarding-mode = disabled",
    
    
    "forwarding-secret-file = forwarding.secret",
    
    
    "motd = OnyxProxy Native"
    
    ) -Encoding UTF8
    }
    $originalServerConfig = Get-Content -Raw -Encoding UTF8 $serverConfigPath
    $serverConfig = $originalServerConfig
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^bind\s*=.*$' -line "bind = 127.0.0.1:$BackendPort"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^forwarding-mode\s*=.*$' -line "forwarding-mode = modern"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^forwarding-secret\s*=.*$' -line "forwarding-secret = $ForwardingSecret"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^forwarding-max-age-seconds\s*=.*$' -line "forwarding-max-age-seconds = 30"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^login-protocol-lock-enabled\s*=.*$' -line "login-protocol-lock-enabled = false"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-enabled\s*=.*$' -line "play-session-enabled = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-duration-ms\s*=.*$' -line "play-session-duration-ms = 150"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-disconnect-on-limit\s*=.*$' -line "play-session-disconnect-on-limit = true"
    Set-Content -Path $serverConfigPath -Value $serverConfig -Encoding UTF8 -NoNewline
    $originalProxyConfig = Get-Content -Raw -Encoding UTF8 $proxyConfigPath
    $proxyConfig = $originalProxyConfig
    $proxyConfig = Upsert-Line -content $proxyConfig -pattern '(?m)^bind\s*=.*$' -line "bind = 127.0.0.1:$ProxyPort"
    $proxyConfig = Upsert-Line -content $proxyConfig -pattern '(?m)^backend\s*=.*$' -line "backend = 127.0.0.1:$BackendPort"
    $proxyConfig = [System.Text.RegularExpressions.Regex]::Replace($proxyConfig, '(?m)^server\.[A-Za-z0-9_.-]+\s*=.*$', '')
    $proxyConfig = Upsert-Line -content $proxyConfig -pattern '(?m)^server\.local\s*=.*$' -line "server.local = 127.0.0.1:$BackendPort"
    $proxyConfig = Upsert-Line -content $proxyConfig -pattern '(?m)^try\s*=.*$' -line "try = local"
    $proxyConfig = Upsert-Line -content $proxyConfig -pattern '(?m)^forwarding-mode\s*=.*$' -line "forwarding-mode = modern"
    $proxyConfig = Upsert-Line -content $proxyConfig -pattern '(?m)^forwarding-secret-file\s*=.*$' -line "forwarding-secret-file = forwarding.secret"
    Set-Content -Path $proxyConfigPath -Value $proxyConfig -Encoding UTF8 -NoNewline
    if (Test-Path $proxySecretPath) {
    
    $hadProxySecret = $true
    
    $originalProxySecret = Get-Content -Raw -Encoding UTF8 $proxySecretPath
    }
    Set-Content -Path $proxySecretPath -Value $ForwardingSecret -Encoding UTF8 -NoNewline
    $server = New-JavaProcess -fileName $JavaBinary -workingDir $serverDir -arguments "-jar onyxserver.jar --config onyxserver.conf --onyx-settings onyx.yml"
    Start-Sleep -Milliseconds 1200
    if ($server.HasExited) {
    
    throw "OnyxServer exited early. stderr: $($server.StandardError.ReadToEnd())"
    }
    Wait-TcpPort -hostName "127.0.0.1" -port $BackendPort -timeoutMs 8000
    $proxy = New-JavaProcess -fileName $JavaBinary -workingDir $proxyDir -arguments "-Donyxproxy.config=onyxproxy.conf -jar onyxproxy.jar"
    Start-Sleep -Milliseconds 1200
    if ($proxy.HasExited) {
    
    throw "OnyxProxy exited early. stderr: $($proxy.StandardError.ReadToEnd())"
    }
    Wait-TcpPort -hostName "127.0.0.1" -port $ProxyPort -timeoutMs 8000
    $uuidBytes = Convert-GuidToNetworkBytes -guid ([Guid]::Parse("00112233-4455-6677-8899-aabbccddeeff"))
    $proxyReason = Invoke-ProxiedLogin -port $ProxyPort -username "AuthPass" -uuidBytes $uuidBytes
    $directResult = Invoke-DirectLoginExpectBlocked -port $BackendPort -username "DirectFail" -uuidBytes $uuidBytes
    $succeeded = $true
    Write-Host "[ONYX] E2E_FORWARDING_AUTH_OK"
    Write-Host "[ONYX] PROXY_PATH_REASON=$proxyReason"
    Write-Host "[ONYX] DIRECT_PATH_RESULT=$directResult"
} finally {
    Stop-JavaProcess -proc $proxy -stopCommand "shutdown"
    Stop-JavaProcess -proc $server -stopCommand "stop"
    if ($server -ne $null) {
    
    try {
    
    
    $serverStdErr = $server.StandardError.ReadToEnd()
    
    } catch {
    
    }
    
    try {
    
    
    $serverStdOut = $server.StandardOutput.ReadToEnd()
    
    } catch {
    
    }
    }
    if ($proxy -ne $null) {
    
    try {
    
    
    $proxyStdErr = $proxy.StandardError.ReadToEnd()
    
    } catch {
    
    }
    
    try {
    
    
    $proxyStdOut = $proxy.StandardOutput.ReadToEnd()
    
    } catch {
    
    }
    }
    if ($null -ne $originalServerConfig) {
    
    Set-Content -Path $serverConfigPath -Value $originalServerConfig -Encoding UTF8 -NoNewline
    }
    if ($null -ne $originalProxyConfig) {
    
    Set-Content -Path $proxyConfigPath -Value $originalProxyConfig -Encoding UTF8 -NoNewline
    }
    if ($hadProxySecret) {
    
    Set-Content -Path $proxySecretPath -Value $originalProxySecret -Encoding UTF8 -NoNewline
    } elseif (Test-Path $proxySecretPath) {
    
    Remove-Item -Force $proxySecretPath
    }
    if (-not $succeeded -and -not [string]::IsNullOrWhiteSpace($serverStdErr)) {
    
    Write-Host "[ONYX] SERVER_STDERR=$serverStdErr"
    }
    if (-not $succeeded -and -not [string]::IsNullOrWhiteSpace($serverStdOut)) {
    
    Write-Host "[ONYX] SERVER_STDOUT=$serverStdOut"
    }
    if (-not $succeeded -and -not [string]::IsNullOrWhiteSpace($proxyStdErr)) {
    
    Write-Host "[ONYX] PROXY_STDERR=$proxyStdErr"
    }
    if (-not $succeeded -and -not [string]::IsNullOrWhiteSpace($proxyStdOut)) {
    
    Write-Host "[ONYX] PROXY_STDOUT=$proxyStdOut"
    }}
