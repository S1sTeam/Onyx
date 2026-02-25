param(
    [switch]$SkipLauncherBuild,
    [switch]$SkipOnyxProxyBuild,
    [switch]$SkipOnyxServerBuild,
    [switch]$SkipOnyxProxyTests,
    [switch]$SkipOnyxServerTests,
    [switch]$NoPackage,
    [switch]$EnableRuntimeDownload,
    [switch]$SkipRuntimeDownload
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) {
    Write-Host "[ONYX] $Message"
}

function Require-Command([string]$CommandName) {
    if (-not (Get-Command $CommandName -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $CommandName"
    }
}

function Invoke-Checked([string]$WorkingDirectory, [string]$Executable, [string[]]$Arguments) {
    Push-Location $WorkingDirectory
    try {
        & $Executable @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed ($LASTEXITCODE): $Executable $($Arguments -join ' ')"
        }
    } finally {
        Pop-Location
    }
}

function Set-ZipEntryFromFile(
    [System.IO.Compression.ZipArchive]$ZipArchive,
    [string]$EntryName,
    [string]$SourceFilePath
) {
    $existing = $ZipArchive.GetEntry($EntryName)
    if ($null -ne $existing) {
        $existing.Delete()
    }

    $entry = $ZipArchive.CreateEntry($EntryName, [System.IO.Compression.CompressionLevel]::NoCompression)
    $entryStream = $entry.Open()
    $sourceStream = [System.IO.File]::OpenRead($SourceFilePath)
    try {
        $sourceStream.CopyTo($entryStream)
    } finally {
        $sourceStream.Dispose()
        $entryStream.Dispose()
    }
}

function Embed-LauncherRuntimes(
    [string]$LauncherJarPath,
    [string]$ProxyJarPath,
    [string]$ServerJarPath
) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::Open($LauncherJarPath, [System.IO.Compression.ZipArchiveMode]::Update)
    try {
        Set-ZipEntryFromFile -ZipArchive $zip -EntryName "embedded/onyxproxy.jar" -SourceFilePath $ProxyJarPath
        Set-ZipEntryFromFile -ZipArchive $zip -EntryName "embedded/onyxserver.jar" -SourceFilePath $ServerJarPath
    } finally {
        $zip.Dispose()
    }
}

function Resolve-Artifact([string]$BuiltJarPath, [string]$RuntimeJarPath, [string]$ArtifactLabel) {
    if (Test-Path $BuiltJarPath) {
        return [PSCustomObject]@{
            Mode = "built"
            Name = (Split-Path -Leaf $BuiltJarPath)
            FullName = (Resolve-Path $BuiltJarPath).Path
        }
    }
    if (Test-Path $RuntimeJarPath) {
        return [PSCustomObject]@{
            Mode = "runtime"
            Name = (Split-Path -Leaf $RuntimeJarPath)
            FullName = (Resolve-Path $RuntimeJarPath).Path
        }
    }
    throw "$ArtifactLabel jar not found. Build from source first."
}

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$distRoot = Join-Path $root "dist"
$launcherTargetJar = Join-Path $root "target/onyx-core.jar"
$nativeProxyRoot = Join-Path $root "native/onyxproxy"
$nativeServerRoot = Join-Path $root "native/onyxserver"

$nativeProxyJar = Join-Path $nativeProxyRoot "target/onyxproxy.jar"
$nativeServerJar = Join-Path $nativeServerRoot "target/onyxserver.jar"

$runtimeProxyJar = Join-Path $root "runtime/onyxproxy/onyxproxy.jar"
$runtimeServerJar = Join-Path $root "runtime/onyxserver/onyxserver.jar"

Require-Command "java"
Require-Command "mvn"

if ($SkipOnyxProxyTests -or $SkipOnyxServerTests) {
    Write-Step "Info: *Tests flags are ignored in native modules; only packaging is run."
}
if ($EnableRuntimeDownload -or $SkipRuntimeDownload) {
    Write-Step "Info: Runtime download flags are deprecated in independent mode and ignored."
}

if (-not (Test-Path (Join-Path $nativeProxyRoot "pom.xml"))) {
    throw "Missing native OnyxProxy source at $nativeProxyRoot"
}
if (-not (Test-Path (Join-Path $nativeServerRoot "pom.xml"))) {
    throw "Missing native OnyxServer source at $nativeServerRoot"
}

if (-not $SkipLauncherBuild) {
    Write-Step "Building Onyx launcher..."
    Invoke-Checked $root "mvn" @("-q", "-DskipTests", "package")
}

if (-not $SkipOnyxProxyBuild) {
    Write-Step "Building native OnyxProxy..."
    Invoke-Checked $nativeProxyRoot "mvn" @("-q", "-DskipTests", "package")
}

if (-not $SkipOnyxServerBuild) {
    Write-Step "Building native OnyxServer..."
    Invoke-Checked $nativeServerRoot "mvn" @("-q", "-DskipTests", "package")
}

if ($NoPackage) {
    Write-Step "NoPackage switch enabled. Build finished without dist packaging."
    exit 0
}

if (-not (Test-Path $launcherTargetJar)) {
    throw "Launcher jar not found: $launcherTargetJar"
}

$proxyArtifact = Resolve-Artifact -BuiltJarPath $nativeProxyJar -RuntimeJarPath $runtimeProxyJar -ArtifactLabel "OnyxProxy"
$serverArtifact = Resolve-Artifact -BuiltJarPath $nativeServerJar -RuntimeJarPath $runtimeServerJar -ArtifactLabel "OnyxServer"

Write-Step "Embedding native runtimes into launcher jar..."
Embed-LauncherRuntimes -LauncherJarPath $launcherTargetJar -ProxyJarPath $proxyArtifact.FullName -ServerJarPath $serverArtifact.FullName

Write-Step "Packaging distribution..."
New-Item -ItemType Directory -Force -Path $distRoot | Out-Null

$distRuntime = Join-Path $distRoot "runtime"
$distLicenses = Join-Path $distRoot "licenses"
if (Test-Path $distRuntime) {
    Remove-Item -Recurse -Force $distRuntime
}
if (Test-Path $distLicenses) {
    Remove-Item -Recurse -Force $distLicenses
}
if (Test-Path (Join-Path $distRoot "onyx-core.jar")) {
    Remove-Item -Force (Join-Path $distRoot "onyx-core.jar")
}
if (Test-Path (Join-Path $distRoot "onyx.properties")) {
    Remove-Item -Force (Join-Path $distRoot "onyx.properties")
}

New-Item -ItemType Directory -Force -Path $distLicenses | Out-Null

Copy-Item -Force $launcherTargetJar (Join-Path $distRoot "server.jar")

$licenseText = @(
    "Onyx Native Distribution",
    "This package contains a single self-extracting Onyx launcher jar with embedded OnyxProxy and OnyxServer runtimes.",
    "Upstream reference folders may exist in the repo history, but are not required for native runtime packaging."
)
Set-Content -Path (Join-Path $distLicenses "onyx-native-NOTICE.txt") -Value $licenseText -Encoding UTF8

$rootCommit = ""
if (Test-Path (Join-Path $root ".git")) {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $rootCommit = (git -C $root rev-parse --verify HEAD 2>$null).Trim()
    }
}
$manifest = @(
    "builtAt=$(Get-Date -Format o)",
    "mode=native",
    "distributionLayout=single-jar-self-extracting",
    "launcherJar=target/onyx-core.jar",
    "onyxCoreCommit=$rootCommit",
    "onyxProxyJar=$($proxyArtifact.Name)",
    "onyxProxyJarSource=$($proxyArtifact.Mode)",
    "onyxServerJar=$($serverArtifact.Name)",
    "onyxServerJarSource=$($serverArtifact.Mode)"
)
Set-Content -Path (Join-Path $distRoot "versions.txt") -Value $manifest -Encoding UTF8

Write-Step "Distribution is ready at: $distRoot"
