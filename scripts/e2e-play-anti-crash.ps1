param(
    [string]$JavaBinary = "java",
    [string]$DistPath = "dist",
    [int]$BackendPort = 48966,
    [int]$MalformedConnections = 160
)

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
    }
}

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
    return $result
}

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
    return $buffer
}

function Write-McString([System.IO.Stream]$stream, [string]$value) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($value)
    Write-VarInt $stream $bytes.Length
    $stream.Write($bytes, 0, $bytes.Length)
}

function Write-UShortBE([System.IO.Stream]$stream, [int]$value) {
    $stream.WriteByte([byte](($value -shr 8) -band 0xFF))
    $stream.WriteByte([byte]($value -band 0xFF))
}

function Build-Packet([ScriptBlock]$writer) {
    $body = New-Object System.IO.MemoryStream
    & $writer $body
    $bodyBytes = $body.ToArray()
    $packet = New-Object System.IO.MemoryStream
    Write-VarInt $packet $bodyBytes.Length
    $packet.Write($bodyBytes, 0, $bodyBytes.Length)
    return $packet.ToArray()
}

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
    return $proc
}

function Stop-JavaProcess($proc, [string]$stopCommand) {
    if ($null -eq $proc -or $proc.HasExited) {
        return
    }
    try {
        $proc.StandardInput.WriteLine($stopCommand)
        $proc.StandardInput.Flush()
    } catch {
    }
    if (-not $proc.WaitForExit(5000)) {
        $proc.Kill()
    }
}

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
    throw "Timeout waiting for ${hostName}:${port}"
}

function Upsert-Line([string]$content, [string]$pattern, [string]$line) {
    if ($content -match $pattern) {
        return [System.Text.RegularExpressions.Regex]::Replace($content, $pattern, $line)
    }
    if ($content.Length -gt 0 -and -not $content.EndsWith("`n")) {
        $content += "`n"
    }
    return $content + $line
}

function Send-RawPacket([string]$hostName, [int]$port, [byte[]]$bytes) {
    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $client.Connect($hostName, $port)
        $stream = $client.GetStream()
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush()
    } catch {
        # Expected for malformed packets; server can close sockets aggressively.
    } finally {
        if ($null -ne $client) {
            try { $client.Close() } catch {}
        }
    }
}

function Assert-StatusHealthy([int]$port) {
    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $client.Connect("127.0.0.1", $port)
        $stream = $client.GetStream()
        $stream.ReadTimeout = 5000

        $handshake = Build-Packet {
            param($packetBody)
            Write-VarInt $packetBody 0x00
            Write-VarInt $packetBody 769
            Write-McString $packetBody "127.0.0.1"
            Write-UShortBE $packetBody $port
            Write-VarInt $packetBody 0x01
        }
        $statusRequest = Build-Packet {
            param($packetBody)
            Write-VarInt $packetBody 0x00
        }

        $stream.Write($handshake, 0, $handshake.Length)
        $stream.Write($statusRequest, 0, $statusRequest.Length)

        $packetLen = Read-VarInt $stream
        $packetBody = Read-Exact $stream $packetLen
        $packetMem = New-Object System.IO.MemoryStream(, $packetBody)
        $packetId = Read-VarInt $packetMem
        if ($packetId -ne 0x00) {
            throw "Unexpected status response packet id: $packetId"
        }
        $jsonLen = Read-VarInt $packetMem
        $jsonBytes = Read-Exact $packetMem $jsonLen
        $json = [System.Text.Encoding]::UTF8.GetString($jsonBytes)
        if ([string]::IsNullOrWhiteSpace($json)) {
            throw "Status JSON is empty after malformed storm"
        }
        if ($json -notmatch '"version"') {
            throw "Status JSON missing version field: $json"
        }
        return $json
    } finally {
        if ($null -ne $client) {
            try { $client.Close() } catch {}
        }
    }
}

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$dist = Join-Path $root $DistPath
$serverDir = Join-Path $dist "runtime/onyxserver"
$serverJar = Join-Path $serverDir "onyxserver.jar"
$serverConfigPath = Join-Path $serverDir "onyxserver.conf"
if (-not (Test-Path $serverJar)) {
    throw "Missing $serverJar. Run scripts/build-onyx.ps1 first."
}
if (-not (Test-Path $serverConfigPath)) {
    throw "Missing $serverConfigPath. Run scripts/run-onyx.ps1 -InitOnly first."
}

$server = $null
$originalServerConfig = $null
try {
    $originalServerConfig = Get-Content -Raw -Encoding UTF8 $serverConfigPath
    $serverConfig = $originalServerConfig
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^bind\s*=.*$' -line "bind = 127.0.0.1:$BackendPort"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^forwarding-mode\s*=.*$' -line "forwarding-mode = disabled"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-protocol-mode\s*=.*$' -line "play-protocol-mode = onyx"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-enabled\s*=.*$' -line "play-session-enabled = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-duration-ms\s*=.*$' -line "play-session-duration-ms = 250"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-poll-timeout-ms\s*=.*$' -line "play-session-poll-timeout-ms = 30"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-max-packets\s*=.*$' -line "play-session-max-packets = 64"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-disconnect-on-limit\s*=.*$' -line "play-session-disconnect-on-limit = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-keepalive-enabled\s*=.*$' -line "play-keepalive-enabled = false"
    Set-Content -Path $serverConfigPath -Value $serverConfig -Encoding UTF8 -NoNewline

    $server = New-JavaProcess -fileName $JavaBinary -workingDir $serverDir -arguments "-jar onyxserver.jar --config onyxserver.conf --onyx-settings onyx.yml"
    Start-Sleep -Milliseconds 1200
    if ($server.HasExited) {
        throw "OnyxServer exited early. stderr: $($server.StandardError.ReadToEnd())"
    }
    Wait-TcpPort -hostName "127.0.0.1" -port $BackendPort -timeoutMs 8000

    $invalidVarInt = [byte[]](0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01)
    # Malformed frame prefix for packet length > MAX_PACKET_SIZE.
    $oversizedMs = New-Object System.IO.MemoryStream
    Write-VarInt $oversizedMs 2097153
    $oversizedPrefix = $oversizedMs.ToArray()
    $truncated = [byte[]](0x02, 0x00, 0x01)
    $garbage = [byte[]](0x7F, 0x7F, 0x7F, 0x00, 0x01)

    for ($i = 0; $i -lt $MalformedConnections; $i++) {
        if ($server.HasExited) {
            throw "OnyxServer exited during malformed storm. stderr: $($server.StandardError.ReadToEnd())"
        }
        switch ($i % 4) {
            0 { Send-RawPacket -hostName "127.0.0.1" -port $BackendPort -bytes $invalidVarInt }
            1 { Send-RawPacket -hostName "127.0.0.1" -port $BackendPort -bytes $oversizedPrefix }
            2 { Send-RawPacket -hostName "127.0.0.1" -port $BackendPort -bytes $truncated }
            Default { Send-RawPacket -hostName "127.0.0.1" -port $BackendPort -bytes $garbage }
        }
    }

    if ($server.HasExited) {
        throw "OnyxServer exited after malformed storm. stderr: $($server.StandardError.ReadToEnd())"
    }
    $statusJson = Assert-StatusHealthy -port $BackendPort
    Write-Host "[ONYX] E2E_PLAY_ANTI_CRASH_OK"
    Write-Host "[ONYX] MALFORMED_CONNECTIONS=$MalformedConnections"
    Write-Host "[ONYX] STATUS_JSON=$statusJson"
} finally {
    Stop-JavaProcess -proc $server -stopCommand "stop"
    if ($null -ne $originalServerConfig) {
        Set-Content -Path $serverConfigPath -Value $originalServerConfig -Encoding UTF8 -NoNewline
    }
}
