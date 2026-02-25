param(
    [string]$JavaBinary = "java",
    [string]$DistPath = "dist",
    [int]$ProxyPort = 25565,
    [int]$BackendPort = 25566 )
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
    
    
    throw "VarInt is too big"
    
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
    
    # Ignore write errors during shutdown.
    }
    if (-not $proc.WaitForExit(5000)) {
    
    $proc.Kill()
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
$socket = $null
try {
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
    
    $portBytes = [System.BitConverter]::GetBytes([uint16]$BackendPort)
    
    [Array]::Reverse($portBytes)
    
    $packetBody.Write($portBytes, 0, 2)
    
    Write-VarInt $packetBody 1
    }
    $statusRequest = Build-Packet {
    
    param($packetBody)
    
    Write-VarInt $packetBody 0
    }
    $pingPayload = [System.BitConverter]::GetBytes([int64]123456789)
    [Array]::Reverse($pingPayload)
    $pingRequest = Build-Packet {
    
    param($packetBody)
    
    Write-VarInt $packetBody 1
    
    $packetBody.Write($pingPayload, 0, $pingPayload.Length)
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
    $stream.Write($pingRequest, 0, $pingRequest.Length)
    $pongLen = Read-VarInt $stream
    $pongBody = Read-Exact $stream $pongLen
    $pongMem = New-Object System.IO.MemoryStream(, $pongBody)
    $pongPacketId = Read-VarInt $pongMem
    if ($pongPacketId -ne 1) {
    
    throw "Unexpected pong packet id: $pongPacketId"
    }
    $pongBytes = Read-Exact $pongMem 8
    [Array]::Reverse($pongBytes)
    $pongValue = [System.BitConverter]::ToInt64($pongBytes, 0)
    if ($json -notmatch '"mode":"native"') {
    
    throw "Status response does not include native marker: $json"
    }
    if ($pongValue -ne 123456789) {
    
    throw "Pong payload mismatch: $pongValue"
    }
    Write-Host "[ONYX] E2E_OK"
    Write-Host "[ONYX] STATUS_JSON=$json"
    Write-Host "[ONYX] PONG=$pongValue"
} finally {
    if ($socket -ne $null) {
    
    $socket.Close()
    }
    Stop-JavaProcess -proc $proxy -stopCommand "shutdown"
    Stop-JavaProcess -proc $server -stopCommand "stop"
}