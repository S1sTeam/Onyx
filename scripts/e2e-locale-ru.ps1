param(
    [string]$JavaBinary = "java",
    [string]$DistPath = "dist" )
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$dist = Join-Path $root $DistPath
$serverJar = Join-Path $dist "server.jar"
$propsPath = Join-Path $dist "onyx.properties"
$proxyConfigPath = Join-Path $dist "runtime/onyxproxy/onyxproxy.conf"
$serverConfigPath = Join-Path $dist "runtime/onyxserver/onyxserver.conf"
$backendGlobalPath = Join-Path $dist "runtime/onyxserver/config/onyx-global.yml"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false )
function Write-Utf8NoBom {
    param(
    
    [Parameter(Mandatory = $true)][string]$Path,
    
    [Parameter(Mandatory = $true)][string]$Value
    )
    [System.IO.File]::WriteAllText($Path, $Value, $utf8NoBom)
}
if (-not (Test-Path $serverJar)) {
    throw "Missing $serverJar. Run scripts/build-onyx.ps1 first."
}
if (-not (Test-Path $propsPath)) {
    throw "Missing $propsPath. Run scripts/run-onyx.ps1 -InitOnly first."}
$originalProps = $null
$originalProxyConfig = $null
$originalServerConfig = $null
$originalBackendGlobal = $null
$proxyConfigExisted = $false
$serverConfigExisted = $false
$backendGlobalExisted = $false
try {
    $originalProps = Get-Content -Raw -Encoding UTF8 $propsPath
    $localeRuProps = if ($originalProps -match '(?m)^system\.locale=') {
    
    [Regex]::Replace($originalProps, '(?m)^system\.locale=.*$', 'system.locale=ru')
    } else {
    
    $originalProps.TrimEnd() + "`nsystem.locale=ru`n"
    }
    Write-Utf8NoBom -Path $propsPath -Value $localeRuProps
    $proxyConfigExisted = Test-Path $proxyConfigPath
    if ($proxyConfigExisted) {
    
    $originalProxyConfig = Get-Content -Raw -Encoding UTF8 $proxyConfigPath
    
    Remove-Item -Path $proxyConfigPath -Force
    }
    $serverConfigExisted = Test-Path $serverConfigPath
    if ($serverConfigExisted) {
    
    $originalServerConfig = Get-Content -Raw -Encoding UTF8 $serverConfigPath
    
    Remove-Item -Path $serverConfigPath -Force
    }
    $backendGlobalExisted = Test-Path $backendGlobalPath
    if ($backendGlobalExisted) {
    
    $originalBackendGlobal = Get-Content -Raw -Encoding UTF8 $backendGlobalPath
    
    Remove-Item -Path $backendGlobalPath -Force
    }
    Push-Location $dist
    try {
    
    $initOutput = & $JavaBinary -jar ".\server.jar" --init-only 2>&1 | Out-String
    } finally {
    
    Pop-Location
    }
    if ($LASTEXITCODE -ne 0) {
    
    throw "Init-only run failed with exit code $LASTEXITCODE. Output: $initOutput"
    }
    if ([string]::IsNullOrWhiteSpace($initOutput)) {
    
    throw "RU locale check failed: init-only produced no output."
    }
    if (-not (Test-Path $proxyConfigPath)) {
    
    throw "RU locale check failed: proxy config not generated."
    }
    if (-not (Test-Path $serverConfigPath)) {
    
    throw "RU locale check failed: server config not generated."
    }
    if (-not (Test-Path $backendGlobalPath)) {
    
    throw "RU locale check failed: backend global config not generated."
    }
    $serverConfig = Get-Content -Raw -Encoding UTF8 $serverConfigPath
    if (-not ($serverConfig -match '(?m)^motd\s*=\s*Onyx .*\p{IsCyrillic}')) {
    
    throw "RU locale check failed: server motd default not localized."
    }
    if (-not ($serverConfig -match '(?m)^play-bootstrap-message\s*=\s*Onyx bootstrap .*\p{IsCyrillic}')) {
    
    throw "RU locale check failed: bootstrap default message not localized."
    }
    $proxyConfig = Get-Content -Raw -Encoding UTF8 $proxyConfigPath
    if (-not ($proxyConfig -match '(?m)^motd\s*=\s*OnyxProxy .*\p{IsCyrillic}')) {
    
    throw "RU locale check failed: proxy motd default not localized."
    }
    $backendGlobal = Get-Content -Raw -Encoding UTF8 $backendGlobalPath
    if (-not ($backendGlobal -match '\p{IsCyrillic}')) {
    
    throw "RU locale check failed: backend global comments not localized."
    }
    Write-Host "[ONYX] E2E_LOCALE_RU_OK"
} finally {
    if ($null -ne $originalProps) {
    
    Write-Utf8NoBom -Path $propsPath -Value $originalProps
    }
    if ($proxyConfigExisted) {
    
    if ($null -ne $originalProxyConfig) {
    
    
    Write-Utf8NoBom -Path $proxyConfigPath -Value $originalProxyConfig
    
    }
    } elseif (Test-Path $proxyConfigPath) {
    
    Remove-Item -Path $proxyConfigPath -Force
    }
    if ($serverConfigExisted) {
    
    if ($null -ne $originalServerConfig) {
    
    
    Write-Utf8NoBom -Path $serverConfigPath -Value $originalServerConfig
    
    }
    } elseif (Test-Path $serverConfigPath) {
    
    Remove-Item -Path $serverConfigPath -Force
    }
    if ($backendGlobalExisted) {
    
    if ($null -ne $originalBackendGlobal) {
    
    
    Write-Utf8NoBom -Path $backendGlobalPath -Value $originalBackendGlobal
    
    }
    } elseif (Test-Path $backendGlobalPath) {
    
    Remove-Item -Path $backendGlobalPath -Force
    }}