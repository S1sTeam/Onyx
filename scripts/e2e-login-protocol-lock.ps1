param(
    [string]$JavaBinary = "java",
    [string]$DistPath = "dist",
    [int]$BackendPort = 48986,
    [int]$AllowedProtocol = 774,
    [int]$RejectedProtocol = 773
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

function Read-McString([System.IO.Stream]$stream) {
    $len = Read-VarInt $stream
    $bytes = Read-Exact $stream $len
    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

function Write-UShortBE([System.IO.Stream]$stream, [int]$value) {
    $stream.WriteByte([byte](($value -shr 8) -band 0xFF))
    $stream.WriteByte([byte]($value -band 0xFF))
}

function Write-UUID([System.IO.Stream]$stream, [Guid]$uuid) {
    $bytes = $uuid.ToByteArray()
    $order = @(3,2,1,0,5,4,7,6,8,9,10,11,12,13,14,15)
    foreach ($index in $order) {
        $stream.WriteByte($bytes[$index])
    }
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

function Send-LoginAndReadFirstPacket([int]$protocol, [string]$username, [int]$port) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $client.Connect("127.0.0.1", $port)
        $stream = $client.GetStream()
        $stream.ReadTimeout = 5000
        $stream.WriteTimeout = 5000

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
            Write-VarInt $packetBody 0x00
            Write-McString $packetBody $username
            Write-UUID $packetBody ([Guid]::NewGuid())
        }

        $stream.Write($handshake, 0, $handshake.Length)
        $stream.Write($loginStart, 0, $loginStart.Length)
        $stream.Flush()

        $packetLen = Read-VarInt $stream
        $packetBody = Read-Exact $stream $packetLen
        $bodyStream = New-Object System.IO.MemoryStream(, $packetBody)
        $packetId = Read-VarInt $bodyStream
        $text = ""
        if ($packetId -eq 0x00) {
            $text = Read-McString $bodyStream
        }
        return [PSCustomObject]@{
            PacketId = $packetId
            Text = $text
        }
    } finally {
        try { $client.Close() } catch {}
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
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^status-protocol-version\s*=.*$' -line "status-protocol-version = $AllowedProtocol"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^login-protocol-lock-enabled\s*=.*$' -line "login-protocol-lock-enabled = true"
    $serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^login-protocol-lock-version\s*=.*$' -line "login-protocol-lock-version = $AllowedProtocol"
    Set-Content -Path $serverConfigPath -Value $serverConfig -Encoding UTF8 -NoNewline

    $server = New-JavaProcess -fileName $JavaBinary -workingDir $serverDir -arguments "-jar onyxserver.jar --config onyxserver.conf --onyx-settings onyx.yml"
    Start-Sleep -Milliseconds 1200
    if ($server.HasExited) {
        throw "OnyxServer exited early. stderr: $($server.StandardError.ReadToEnd())"
    }
    Wait-TcpPort -hostName "127.0.0.1" -port $BackendPort -timeoutMs 8000

    $allowed = Send-LoginAndReadFirstPacket -protocol $AllowedProtocol -username "LockAllow" -port $BackendPort
    if ($allowed.PacketId -ne 0x02) {
        throw "Allowed protocol $AllowedProtocol did not return LoginSuccess (0x02). Got packet id 0x$([Convert]::ToString($allowed.PacketId,16))."
    }

    $rejected = Send-LoginAndReadFirstPacket -protocol $RejectedProtocol -username "LockDeny" -port $BackendPort
    if ($rejected.PacketId -ne 0x00) {
        throw "Rejected protocol $RejectedProtocol did not return LoginDisconnect (0x00). Got packet id 0x$([Convert]::ToString($rejected.PacketId,16))."
    }
    if ($rejected.Text -notmatch [regex]::Escape("$AllowedProtocol")) {
        throw "Reject reason does not mention expected protocol ${AllowedProtocol}: $($rejected.Text)"
    }

    Write-Host "[ONYX] E2E_LOGIN_PROTOCOL_LOCK_OK"
    Write-Host "[ONYX] ALLOWED_PROTOCOL=$AllowedProtocol"
    Write-Host "[ONYX] REJECTED_PROTOCOL=$RejectedProtocol"
} finally {
    Stop-JavaProcess -proc $server -stopCommand "stop"
    if ($null -ne $originalServerConfig) {
        Set-Content -Path $serverConfigPath -Value $originalServerConfig -Encoding UTF8 -NoNewline
    }
}
