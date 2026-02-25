param(
    [string]$JavaBinary = "java",
    [string]$DistPath = "dist",
    [int]$BackendPort = 40566 )
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$Protocol = 769
$DisconnectPacketId = 0x1D
$LoginAckPacketId = 0x03
$ConfigFinishPacketId = 0x03
$ChatPacketId = 0x73
$CommandPacketId = 0x74
$ResponsePacketId = 0x6C
$ExpectedUsername = "PluginRegProbe"
$ExpectedHelpCommand = "help"
$ExpectedPluginCommand = "hello"
$ExpectedHelpResponsePrefix = "Onyx cmds:"
$ExpectedPluginResponse = "Onyx plugin hello PluginRegProbe"
$SpawnX = 2.5
$SpawnY = 70.0
$SpawnZ = -3.0
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
function Resolve-JdkTool([string]$toolName) {
    if (-not [string]::IsNullOrWhiteSpace($JavaBinary)) {
    
    try {
    
    
    $javaPath = (Get-Command $JavaBinary -ErrorAction Stop).Source
    
    
    $javaDir = Split-Path -Parent $javaPath
    
    
    $candidate = Join-Path $javaDir "$toolName.exe"
    
    
    if (Test-Path $candidate) {
    
    
    
    return $candidate
    
    
    }
    
    } catch {
    
    }
    }
    if (-not [string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
    
    $candidate = Join-Path $env:JAVA_HOME "bin/$toolName.exe"
    
    if (Test-Path $candidate) {
    
    
    return $candidate
    
    }
    }
    return $toolName}
function Build-E2EPluginCommandRegistryPlugin([string]$serverJarPath, [string]$pluginsDir) {
    $javac = Resolve-JdkTool "javac"
    $workDir = Join-Path $pluginsDir "_e2e_plugin_command_registry_build"
    if (Test-Path $workDir) {
    
    Remove-Item -Recurse -Force $workDir
    }
    New-Item -ItemType Directory -Path $workDir | Out-Null
    $srcDir = Join-Path $workDir "src/dev/onyx/e2e"
    $servicesDir = Join-Path $workDir "services/META-INF/services"
    $classesDir = Join-Path $workDir "classes"
    New-Item -ItemType Directory -Path $srcDir -Force | Out-Null
    New-Item -ItemType Directory -Path $servicesDir -Force | Out-Null
    New-Item -ItemType Directory -Path $classesDir -Force | Out-Null
    $sourcePath = Join-Path $srcDir "E2EPluginCommandRegistryPlugin.java"
    $servicePath = Join-Path $servicesDir "dev.onyx.server.plugin.OnyxServerPlugin"
    $pluginJarPath = Join-Path $pluginsDir "e2e-plugin-command-registry.jar"
    $source = @'
package dev.onyx.e2e;

import dev.onyx.server.plugin.OnyxServerCommandResult;
import dev.onyx.server.plugin.OnyxServerContext;
import dev.onyx.server.plugin.OnyxServerPlugin;

public final class E2EPluginCommandRegistryPlugin implements OnyxServerPlugin {
    @Override
    public String id() {
        return "e2e-plugin-command-registry";
    }

    @Override
    public void onEnable(OnyxServerContext context) {
        context.registerCommand("hello", input ->
            OnyxServerCommandResult.consume("Onyx plugin hello " + input.username())
        );
        context.logger().info("E2E plugin command registry enabled");
    }
}
'@
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($sourcePath, $source, $utf8NoBom)
    [System.IO.File]::WriteAllText($servicePath, "dev.onyx.e2e.E2EPluginCommandRegistryPlugin", $utf8NoBom)
    & $javac --release 21 -cp $serverJarPath -d $classesDir $sourcePath
    if ($LASTEXITCODE -ne 0) {
    
    throw "javac failed while building e2e plugin command registry plugin"
    }
    Copy-Item -Path (Join-Path $workDir "services/META-INF") -Destination $classesDir -Recurse -Force
    if (Test-Path $pluginJarPath) {
    
    Remove-Item -Force $pluginJarPath
    }
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $jarStream = [System.IO.File]::Open($pluginJarPath, [System.IO.FileMode]::CreateNew)
    $zip = New-Object System.IO.Compression.ZipArchive($jarStream, [System.IO.Compression.ZipArchiveMode]::Create, $false)
    try {
    
    Get-ChildItem -Path $classesDir -Recurse -File | ForEach-Object {
    
    
    $relative = $_.FullName.Substring($classesDir.Length + 1).Replace('\', '/')
    
    
    $entry = $zip.CreateEntry($relative, [System.IO.Compression.CompressionLevel]::Optimal)
    
    
    $entryStream = $entry.Open()
    
    
    $fileStream = [System.IO.File]::OpenRead($_.FullName)
    
    
    try {
    
    
    
    $fileStream.CopyTo($entryStream)
    
    
    } finally {
    
    
    
    $fileStream.Dispose()
    
    
    
    $entryStream.Dispose()
    
    
    }
    
    }
    } finally {
    
    $zip.Dispose()
    
    $jarStream.Dispose()
    }
    if (-not (Test-Path $pluginJarPath)) {
    
    throw "failed to pack e2e plugin command registry plugin jar"
    }
    $zip = [System.IO.Compression.ZipFile]::OpenRead($pluginJarPath)
    try {
    
    $entryNames = @($zip.Entries | ForEach-Object { $_.FullName })
    
    if ($entryNames -notcontains "META-INF/services/dev.onyx.server.plugin.OnyxServerPlugin") {
    
    
    throw "plugin jar missing ServiceLoader entry"
    
    }
    
    if ($entryNames -notcontains "dev/onyx/e2e/E2EPluginCommandRegistryPlugin.class") {
    
    
    throw "plugin jar missing plugin class entry"
    
    }
    } finally {
    
    $zip.Dispose()
    }
    return [PSCustomObject]@{
    
    PluginJarPath = $pluginJarPath
    
    BuildDir = $workDir
    }}
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$dist = Join-Path $root $DistPath
$serverDir = Join-Path $dist "runtime/onyxserver"
$serverJar = Join-Path $serverDir "onyxserver.jar"
$serverConfigPath = Join-Path $serverDir "onyxserver.conf"
$serverPluginsDir = Join-Path $serverDir "plugins"
if (-not (Test-Path $serverJar)) {
    throw "Missing $serverJar. Run scripts/build-onyx.ps1 first."
}
if (-not (Test-Path $serverConfigPath)) {
    throw "Missing $serverConfigPath. Run scripts/run-onyx.ps1 -InitOnly first."}
$server = $null
$client = $null
$originalServerConfig = $null
$pluginArtifact = $null
$testPassed = $false
try {
    if (-not (Test-Path $serverPluginsDir)) {
    
    New-Item -ItemType Directory -Path $serverPluginsDir | Out-Null
    }
    $pluginArtifact = Build-E2EPluginCommandRegistryPlugin -serverJarPath $serverJar -pluginsDir $serverPluginsDir
    $originalServerConfig = Get-Content -Raw -Encoding UTF8 $serverConfigPath
    $serverConfig = $originalServerConfig
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^bind\s*=.*$' -line "bind = 127.0.0.1:$BackendPort"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^forwarding-mode\s*=.*$' -line "forwarding-mode = disabled"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-enabled\s*=.*$' -line "play-session-enabled = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-duration-ms\s*=.*$' -line "play-session-duration-ms = 900"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-poll-timeout-ms\s*=.*$' -line "play-session-poll-timeout-ms = 50"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-max-packets\s*=.*$' -line "play-session-max-packets = 128"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-disconnect-on-limit\s*=.*$' -line "play-session-disconnect-on-limit = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-enabled\s*=.*$' -line "play-bootstrap-enabled = false"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-format\s*=.*$' -line "play-bootstrap-format = onyx"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-message-packet-id\s*=.*$' -line "play-bootstrap-message-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-spawn-x\s*=.*$' -line "play-bootstrap-spawn-x = $SpawnX"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-spawn-y\s*=.*$' -line "play-bootstrap-spawn-y = $SpawnY"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-spawn-z\s*=.*$' -line "play-bootstrap-spawn-z = $SpawnZ"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-movement-enabled\s*=.*$' -line "play-movement-enabled = false"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-input-enabled\s*=.*$' -line "play-input-enabled = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-input-chat-packet-id\s*=.*$' -line "play-input-chat-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-input-command-packet-id\s*=.*$' -line "play-input-command-packet-id = -1"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-input-max-message-length\s*=.*$' -line "play-input-max-message-length = 64"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-input-chat-dispatch-commands\s*=.*$' -line "play-input-chat-dispatch-commands = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-input-chat-command-prefix\s*=.*$' -line "play-input-chat-command-prefix = /"
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
    $helpPacket = Build-Packet {
    
    param($packetBody)
    
    Write-VarInt $packetBody $CommandPacketId
    
    Write-McString $packetBody $ExpectedHelpCommand
    }
    $stream.Write($helpPacket, 0, $helpPacket.Length)
    $pluginCommandPacket = Build-Packet {
    
    param($packetBody)
    
    Write-VarInt $packetBody $CommandPacketId
    
    Write-McString $packetBody $ExpectedPluginCommand
    }
    $stream.Write($pluginCommandPacket, 0, $pluginCommandPacket.Length)
    $sentHelpCommand = $true
    $sentPluginCommand = $true
    $receivedHelpResponse = $false
    $receivedPluginResponse = $false
    $disconnectReason = ""
    $maxPackets = 128
    for ($i = 0; $i -lt $maxPackets; $i++) {
    
    $packet = Read-Packet $stream
    
    if ($packet.Id -eq $ResponsePacketId) {
    
    
    $responseText = Read-McString $packet.Stream
    
    
    if ($responseText.StartsWith($ExpectedHelpResponsePrefix)) {
    
    
    
    $receivedHelpResponse = $true
    
    
    }
    
    
    if ($responseText -eq $ExpectedPluginResponse) {
    
    
    
    $receivedPluginResponse = $true
    
    
    }
    
    
    continue
    
    }
    
    if ($packet.Id -eq $DisconnectPacketId) {
    
    
    $disconnectReason = Read-AnonymousNbtText $packet.Stream
    
    
    break
    
    }
    }
    if (-not $sentHelpCommand) {
    
    throw "Help command packet was not sent"
    }
    if (-not $sentPluginCommand) {
    
    throw "Plugin command packet was not sent"
    }
    if ([string]::IsNullOrWhiteSpace($disconnectReason)) {
    
    throw "Did not receive final disconnect packet"
    }
    if ($disconnectReason -notmatch 'input-packets=2') {
    
    throw "Server did not report input packet total: $disconnectReason"
    }
    if ($disconnectReason -notmatch 'input-chat-packets=0') {
    
    throw "Server did not record chat packet count: $disconnectReason"
    }
    if ($disconnectReason -notmatch 'input-command-packets=2') {
    
    throw "Server did not record command packet total: $disconnectReason"
    }
    if ($disconnectReason -notmatch 'input-chat-command-packets=0') {
    
    throw "Server did not report chat-command packet count: $disconnectReason"
    }
    if ($disconnectReason -notmatch 'input-direct-command-packets=2') {
    
    throw "Server did not report direct-command packet total: $disconnectReason"
    }
    if ($disconnectReason -notmatch 'input-plugin-chat-handled=0') {
    
    throw "Server did not report plugin chat handled count: $disconnectReason"
    }
    if ($disconnectReason -notmatch 'input-plugin-command-handled=0') {
    
    throw "Server did not report plugin command handled count: $disconnectReason"
    }
    if ($disconnectReason -notmatch 'input-command-help=1') {
    
    throw "Server did not record built-in help command count: $disconnectReason"
    }
    if ($disconnectReason -notmatch 'input-command-plugin=1') {
    
    throw "Server did not record plugin command dispatch count: $disconnectReason"
    }
    if ($disconnectReason -notmatch 'input-command-unknown=0') {
    
    throw "Server reported unexpected unknown command count: $disconnectReason"
    }
    if ($disconnectReason -notmatch 'input-response-packets=2') {
    
    throw "Server did not record input response packet count: $disconnectReason"
    }
    if ($disconnectReason -notmatch 'input-plugin-response-packets=0') {
    
    throw "Server did not record plugin response packet count: $disconnectReason"
    }
    if ($disconnectReason -notmatch 'input-last-command=hello') {
    
    throw "Server did not report expected last command: $disconnectReason"
    }
    if (-not $receivedHelpResponse) {
    
    throw "Did not receive expected help response packet"
    }
    if (-not $receivedPluginResponse) {
    
    throw "Did not receive expected plugin command response packet"
    }
    $testPassed = $true
    Write-Host "[ONYX] E2E_PLAY_PLUGIN_COMMAND_REGISTRY_OK"
    Write-Host "[ONYX] DISCONNECT_REASON=$disconnectReason"
} finally {
    if ($client -ne $null) {
    
    $client.Close()
    }
    Stop-JavaProcess -proc $server -stopCommand "stop"
    if ($server -ne $null) {
    
    try {
    
    
    $serverStdout = $server.StandardOutput.ReadToEnd()
    
    
    $serverStderr = $server.StandardError.ReadToEnd()
    
    
    if (-not $testPassed) {
    
    
    
    if (-not [string]::IsNullOrWhiteSpace($serverStdout)) {
    
    
    
    
    Write-Host "[ONYX] SERVER_STDOUT_BEGIN"
    
    
    
    
    Write-Host $serverStdout
    
    
    
    
    Write-Host "[ONYX] SERVER_STDOUT_END"
    
    
    
    }
    
    
    
    if (-not [string]::IsNullOrWhiteSpace($serverStderr)) {
    
    
    
    
    Write-Host "[ONYX] SERVER_STDERR_BEGIN"
    
    
    
    
    Write-Host $serverStderr
    
    
    
    
    Write-Host "[ONYX] SERVER_STDERR_END"
    
    
    
    }
    
    
    }
    
    } catch {
    
    }
    }
    if ($null -ne $pluginArtifact) {
    
    if (Test-Path $pluginArtifact.PluginJarPath) {
    
    
    Remove-Item -Force $pluginArtifact.PluginJarPath
    
    }
    
    if (Test-Path $pluginArtifact.BuildDir) {
    
    
    Remove-Item -Recurse -Force $pluginArtifact.BuildDir
    
    }
    }
    if ($null -ne $originalServerConfig) {
    
    Set-Content -Path $serverConfigPath -Value $originalServerConfig -Encoding UTF8 -NoNewline
    }}