param(
    [string]$JavaBinary = "java",
    [string]$DistPath = "dist",
    [int]$ProxyPort = 28565,
    [int]$HubPort = 28566,
    [int]$GamePort = 28567,
    [int]$DeadPort = 28568 )
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
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
function Build-Packet([ScriptBlock]$writer) {
    $body = New-Object System.IO.MemoryStream
    & $writer $body
    $bodyBytes = $body.ToArray()
    $packet = New-Object System.IO.MemoryStream
    Write-VarInt $packet $bodyBytes.Length
    $packet.Write($bodyBytes, 0, $bodyBytes.Length)
    return $packet.ToArray()}
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
function Invoke-StatusRequest([int]$port, [string]$hostField) {
    $socket = New-Object System.Net.Sockets.TcpClient
    try {
    
    $socket.Connect("127.0.0.1", $port)
    
    $stream = $socket.GetStream()
    
    $handshake = Build-Packet {
    
    
    param($packetBody)
    
    
    Write-VarInt $packetBody 0
    
    
    Write-VarInt $packetBody 769
    
    
    $hostBytes = [System.Text.Encoding]::UTF8.GetBytes($hostField)
    
    
    Write-VarInt $packetBody $hostBytes.Length
    
    
    $packetBody.Write($hostBytes, 0, $hostBytes.Length)
    
    
    $portBytes = [System.BitConverter]::GetBytes([uint16]$port)
    
    
    [Array]::Reverse($portBytes)
    
    
    $packetBody.Write($portBytes, 0, 2)
    
    
    Write-VarInt $packetBody 1
    
    }
    
    $statusRequest = Build-Packet {
    
    
    param($packetBody)
    
    
    Write-VarInt $packetBody 0
    
    }
    
    $stream.Write($handshake, 0, $handshake.Length)
    
    $stream.Write($statusRequest, 0, $statusRequest.Length)
    
    $statusLen = Read-VarInt $stream
    
    $statusBody = Read-Exact $stream $statusLen
    
    $statusMem = New-Object System.IO.MemoryStream(, $statusBody)
    
    $statusPacketId = Read-VarInt $statusMem
    
    if ($statusPacketId -ne 0) {
    
    
    throw "Unexpected status packet id: $statusPacketId"
    
    }
    
    $jsonLen = Read-VarInt $statusMem
    
    $jsonBytes = Read-Exact $statusMem $jsonLen
    
    $json = [System.Text.Encoding]::UTF8.GetString($jsonBytes)
    
    return $json
    } finally {
    
    $socket.Close()
    }}
function Write-ServerConfig([string]$path, [int]$port, [string]$motd) {
    $lines = @(
    
    "# OnyxServer native config",
    
    "version = 1",
    
    "bind = 127.0.0.1:$port",
    
    "motd = $motd",
    
    "max-players = 100",
    
    "status-version-name = Onyx Native",
    
    "status-protocol-version = -1",
    
    "forwarding-mode = disabled",
    
    "forwarding-max-age-seconds = 30"
    )
    Set-Content -Path $path -Value $lines -Encoding UTF8}
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$dist = Join-Path $root $DistPath
$proxyDir = Join-Path $dist "runtime/onyxproxy"
$baseServerDir = Join-Path $dist "runtime/onyxserver"
$hubDir = Join-Path $dist "runtime/onyxserver-hub"
$gameDir = Join-Path $dist "runtime/onyxserver-game"
$proxyJar = Join-Path $proxyDir "onyxproxy.jar"
$serverJar = Join-Path $baseServerDir "onyxserver.jar"
$proxyConfigPath = Join-Path $proxyDir "onyxproxy.conf"
if (-not (Test-Path $proxyJar)) {
    throw "Missing $proxyJar. Run scripts/build-onyx.ps1 first."
}
if (-not (Test-Path $serverJar)) {
    throw "Missing $serverJar. Run scripts/build-onyx.ps1 first."
}
if (-not (Test-Path $proxyConfigPath)) {
    throw "Missing $proxyConfigPath. Run scripts/run-onyx.ps1 -InitOnly first."}
$hub = $null
$game = $null
$proxy = $null
$originalProxyConfig = $null
$proxyStdErr = ""
$proxyStdOut = ""
try {
    New-Item -ItemType Directory -Force -Path $hubDir | Out-Null
    New-Item -ItemType Directory -Force -Path $gameDir | Out-Null
    Copy-Item -Force $serverJar (Join-Path $hubDir "onyxserver.jar")
    Copy-Item -Force $serverJar (Join-Path $gameDir "onyxserver.jar")
    Write-ServerConfig -path (Join-Path $hubDir "onyxserver.conf") -port $HubPort -motd "Onyx Hub Backend"
    Write-ServerConfig -path (Join-Path $gameDir "onyxserver.conf") -port $GamePort -motd "Onyx Game Backend"
    $originalProxyConfig = Get-Content -Raw -Encoding UTF8 $proxyConfigPath
    $proxyConfig = @(
    
    "# OnyxProxy native config",
    
    "version = 1",
    
    "bind = 127.0.0.1:$ProxyPort",
    
    "backend = 127.0.0.1:$HubPort",
    
    "server.hub = 127.0.0.1:$HubPort",
    
    "server.game = 127.0.0.1:$GamePort",
    
    "server.dead = 127.0.0.1:$DeadPort",
    
    "try = game,hub",
    
    "route.hub.local = hub",
    
    "route.game.local = dead,game",
    
    "route.default = hub",
    
    "motd = OnyxProxy Native"
    ) -join "`n"
    Set-Content -Path $proxyConfigPath -Value $proxyConfig -Encoding UTF8 -NoNewline
    $hub = New-JavaProcess -fileName $JavaBinary -workingDir $hubDir -arguments "-jar onyxserver.jar --config onyxserver.conf --onyx-settings onyx.yml"
    $game = New-JavaProcess -fileName $JavaBinary -workingDir $gameDir -arguments "-jar onyxserver.jar --config onyxserver.conf --onyx-settings onyx.yml"
    Start-Sleep -Milliseconds 1200
    if ($hub.HasExited) {
    
    throw "Hub backend exited early. stderr: $($hub.StandardError.ReadToEnd())"
    }
    if ($game.HasExited) {
    
    throw "Game backend exited early. stderr: $($game.StandardError.ReadToEnd())"
    }
    Wait-TcpPort -hostName "127.0.0.1" -port $HubPort -timeoutMs 8000
    Wait-TcpPort -hostName "127.0.0.1" -port $GamePort -timeoutMs 8000
    $proxy = New-JavaProcess -fileName $JavaBinary -workingDir $proxyDir -arguments "-Donyxproxy.config=onyxproxy.conf -jar onyxproxy.jar"
    Start-Sleep -Milliseconds 1200
    if ($proxy.HasExited) {
    
    throw "OnyxProxy exited early. stderr: $($proxy.StandardError.ReadToEnd())"
    }
    Wait-TcpPort -hostName "127.0.0.1" -port $ProxyPort -timeoutMs 8000
    $hubJson = Invoke-StatusRequest -port $ProxyPort -hostField "hub.local"
    $gameJson = Invoke-StatusRequest -port $ProxyPort -hostField "game.local"
    $defaultJson = Invoke-StatusRequest -port $ProxyPort -hostField "unknown.local"
    if ($hubJson -notmatch 'Onyx Hub Backend') {
    
    throw "Routing mismatch for hub.local: $hubJson"
    }
    if ($gameJson -notmatch 'Onyx Game Backend') {
    
    throw "Routing mismatch for game.local: $gameJson"
    }
    if ($defaultJson -notmatch 'Onyx Hub Backend') {
    
    throw "Default routing mismatch for unknown.local: $defaultJson"
    }
    Write-Host "[ONYX] E2E_PROXY_ROUTING_OK"
    Write-Host "[ONYX] HUB_JSON=$hubJson"
    Write-Host "[ONYX] GAME_JSON=$gameJson"
    Write-Host "[ONYX] DEFAULT_JSON=$defaultJson"
} finally {
    Stop-JavaProcess -proc $proxy -stopCommand "shutdown"
    Stop-JavaProcess -proc $hub -stopCommand "stop"
    Stop-JavaProcess -proc $game -stopCommand "stop"
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
    if ($null -ne $originalProxyConfig) {
    
    Set-Content -Path $proxyConfigPath -Value $originalProxyConfig -Encoding UTF8 -NoNewline
    }
    if (Test-Path $hubDir) {
    
    Remove-Item -Recurse -Force $hubDir
    }
    if (Test-Path $gameDir) {
    
    Remove-Item -Recurse -Force $gameDir
    }
    if (-not [string]::IsNullOrWhiteSpace($proxyStdErr)) {
    
    Write-Host "[ONYX] PROXY_STDERR=$proxyStdErr"
    }
    if (-not [string]::IsNullOrWhiteSpace($proxyStdOut)) {
    
    Write-Host "[ONYX] PROXY_STDOUT=$proxyStdOut"
    }}