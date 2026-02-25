param(
    [string]$DistPath = "dist",
    [int]$ProtocolVersion = 774,
    [switch]$DisableLoginProtocolLock
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($ProtocolVersion -lt 47) {
    throw "ProtocolVersion must be >= 47."
}
$loginProtocolLockEnabled = -not $DisableLoginProtocolLock
$loginProtocolLockEnabledText = if ($loginProtocolLockEnabled) { "true" } else { "false" }

function Upsert-Line([string]$content, [string]$pattern, [string]$line) {
    if ($content -match $pattern) {
        return [System.Text.RegularExpressions.Regex]::Replace($content, $pattern, $line)
    }
    if ($content.Length -gt 0 -and -not $content.EndsWith("`n")) {
        $content += "`n"
    }
    return $content + $line
}

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$dist = Join-Path $root $DistPath
$serverConfigPath = Join-Path $dist "runtime/onyxserver/onyxserver.conf"
$proxyConfigPath = Join-Path $dist "runtime/onyxproxy/onyxproxy.conf"

if (-not (Test-Path $serverConfigPath)) {
    throw "Missing $serverConfigPath. Run scripts/run-onyx.ps1 -InitOnly first."
}
if (-not (Test-Path $proxyConfigPath)) {
    throw "Missing $proxyConfigPath. Run scripts/run-onyx.ps1 -InitOnly first."
}

$serverConfig = Get-Content -Raw -Encoding UTF8 $serverConfigPath
$serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^status-protocol-version\s*=.*$' -line "status-protocol-version = $ProtocolVersion"
$serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^login-protocol-lock-enabled\s*=.*$' -line "login-protocol-lock-enabled = $loginProtocolLockEnabledText"
$serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^login-protocol-lock-version\s*=.*$' -line "login-protocol-lock-version = $ProtocolVersion"
$serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-protocol-mode\s*=.*$' -line "play-protocol-mode = vanilla"
$serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-enabled\s*=.*$' -line "play-session-enabled = true"
$serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-persistent\s*=.*$' -line "play-session-persistent = true"
$serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-disconnect-on-limit\s*=.*$' -line "play-session-disconnect-on-limit = false"
$serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-session-idle-timeout-ms\s*=.*$' -line "play-session-idle-timeout-ms = 600000"
$serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-keepalive-enabled\s*=.*$' -line "play-keepalive-enabled = true"
$serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-keepalive-require-ack\s*=.*$' -line "play-keepalive-require-ack = true"
$serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-bootstrap-enabled\s*=.*$' -line "play-bootstrap-enabled = true"
$serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-movement-enabled\s*=.*$' -line "play-movement-enabled = true"
$serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-input-enabled\s*=.*$' -line "play-input-enabled = true"
$serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-input-rate-limit-enabled\s*=.*$' -line "play-input-rate-limit-enabled = true"
$serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-input-response-enabled\s*=.*$' -line "play-input-response-enabled = true"
$serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-world-enabled\s*=.*$' -line "play-world-enabled = true"
$serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-entity-enabled\s*=.*$' -line "play-entity-enabled = true"
$serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-inventory-enabled\s*=.*$' -line "play-inventory-enabled = true"
$serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-interact-enabled\s*=.*$' -line "play-interact-enabled = true"
$serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-combat-enabled\s*=.*$' -line "play-combat-enabled = true"
$serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-engine-enabled\s*=.*$' -line "play-engine-enabled = true"
$serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-persistence-enabled\s*=.*$' -line "play-persistence-enabled = true"
$serverConfig = Upsert-Line -content $serverConfig -pattern '(?m)^play-persistence-autosave-interval-ms\s*=.*$' -line "play-persistence-autosave-interval-ms = 5000"
Set-Content -Path $serverConfigPath -Value $serverConfig -Encoding UTF8 -NoNewline

$proxyConfig = Get-Content -Raw -Encoding UTF8 $proxyConfigPath
$proxyConfig = Upsert-Line -content $proxyConfig -pattern '(?m)^max-connections-per-ip\s*=.*$' -line "max-connections-per-ip = 8"
$proxyConfig = Upsert-Line -content $proxyConfig -pattern '(?m)^connect-timeout-ms\s*=.*$' -line "connect-timeout-ms = 5000"
$proxyConfig = Upsert-Line -content $proxyConfig -pattern '(?m)^first-packet-timeout-ms\s*=.*$' -line "first-packet-timeout-ms = 8000"
$proxyConfig = Upsert-Line -content $proxyConfig -pattern '(?m)^backend-connect-attempts\s*=.*$' -line "backend-connect-attempts = 3"
Set-Content -Path $proxyConfigPath -Value $proxyConfig -Encoding UTF8 -NoNewline

Write-Host "[ONYX] FINISHED_V1_PROFILE_OK"
Write-Host "[ONYX] STATUS_PROTOCOL=$ProtocolVersion"
Write-Host "[ONYX] LOGIN_PROTOCOL_LOCK=$loginProtocolLockEnabledText"
Write-Host "[ONYX] PLAY_PROTOCOL_MODE=vanilla"
