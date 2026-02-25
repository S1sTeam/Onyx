param(
    [string]$JavaBinary = "java",
    [string]$DistPath = "dist",
    [int]$ProxyPort = 27565,
    [int]$DownBackendPort = 27566,
    [int]$LiveBackendPort = 27567 )
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
$socket = $null
$serverConfigPath = Join-Path $serverDir "onyxserver.conf"
$proxyConfigPath = Join-Path $proxyDir "onyxproxy.conf"
$originalServerConfig = $null
$originalProxyConfig = $null
try {
    if (-not (Test-Path $serverConfigPath)) {
    
    throw "Missing $serverConfigPath. Run scripts/run-onyx.ps1 -InitOnly first."
    }
    if (-not (Test-Path $proxyConfigPath)) {
    
    throw "Missing $proxyConfigPath. Run scripts/run-onyx.ps1 -InitOnly first."
    }
    $originalServerConfig = Get-Content -Raw -Encoding UTF8 $serverConfigPath
    $serverConfig = [System.Text.RegularExpressions.Regex]::Replace($originalServerConfig, '(?m)^bind\s*=.*$', "bind = 127.0.0.1:$LiveBackendPort")
    Set-Content -Path $serverConfigPath -Value $serverConfig -Encoding UTF8 -NoNewline
    $originalProxyConfig = Get-Content -Raw -Encoding UTF8 $proxyConfigPath
    $proxyConfig = $originalProxyConfig
    $proxyConfig = [System.Text.RegularExpressions.Regex]::Replace($proxyConfig, '(?m)^bind\s*=.*$', "bind = 127.0.0.1:$ProxyPort")
    $proxyConfig = [System.Text.RegularExpressions.Regex]::Replace($proxyConfig, '(?m)^backend\s*=.*$', "backend = 127.0.0.1:$DownBackendPort")
    $proxyConfig = [System.Text.RegularExpressions.Regex]::Replace($proxyConfig, '(?m)^server\.[A-Za-z0-9_.-]+\s*=.*$', '')
    $proxyConfig += "`nserver.primary = 127.0.0.1:$DownBackendPort"
    $proxyConfig += "`nserver.secondary = 127.0.0.1:$LiveBackendPort"
    $proxyConfig = [System.Text.RegularExpressions.Regex]::Replace($proxyConfig, '(?m)^try\s*=.*$', "try = primary,secondary")
    if ($proxyConfig -notmatch '(?m)^try\s*=') {
    
    $proxyConfig += "`ntry = primary,secondary"
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
    $socket = New-Object System.Net.Sockets.TcpClient
    $socket.Connect("127.0.0.1", $ProxyPort)
    $stream = $socket.GetStream()
    $handshake = Build-Packet {
    
    param($packetBody)
    
    Write-VarInt $packetBody 0
    
    Write-VarInt $packetBody 769
    
    $hostBytes = [System.Text.Encoding]::UTF8.GetBytes("127.0.0.1")
    
    Write-VarInt $packetBody $hostBytes.Length
    
    $packetBody.Write($hostBytes, 0, $hostBytes.Length)
    
    $portBytes = [System.BitConverter]::GetBytes([uint16]$ProxyPort)
    
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
    if ($json -notmatch '"mode":"native"') {
    
    throw "Status response does not include native marker: $json"
    }
    Write-Host "[ONYX] E2E_PROXY_FAILOVER_OK"
    Write-Host "[ONYX] STATUS_JSON=$json"
} finally {
    if ($socket -ne $null) {
    
    $socket.Close()
    }
    Stop-JavaProcess -proc $proxy -stopCommand "shutdown"
    Stop-JavaProcess -proc $server -stopCommand "stop"
    if ($null -ne $originalServerConfig) {
    
    Set-Content -Path $serverConfigPath -Value $originalServerConfig -Encoding UTF8 -NoNewline
    }
    if ($null -ne $originalProxyConfig) {
    
    Set-Content -Path $proxyConfigPath -Value $originalProxyConfig -Encoding UTF8 -NoNewline
    }}