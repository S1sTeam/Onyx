param(
    [string]$JavaBinary = "java",
    [string]$DistPath = "dist",
    [int]$Iterations = 3,
    [int]$BaseBackendPort = 49100,
    [int]$PortStridePerIteration = 400,
    [int]$DelayMsBetweenRuns = 200,
    [string]$ReportPath = "",
    [string[]]$OnlyTests = @(),
    [int]$MaxAttemptsPerTest = 2,
    [int]$RetryPortBump = 1000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($Iterations -lt 1) {
    throw "Iterations must be >= 1."
}
if ($MaxAttemptsPerTest -lt 1) {
    throw "MaxAttemptsPerTest must be >= 1."
}
if ($RetryPortBump -lt 1) {
    throw "RetryPortBump must be >= 1."
}

function Get-Percentile([double[]]$values, [double]$percentile) {
    if ($values.Count -eq 0) {
        return [double]::NaN
    }
    $sorted = @($values | Sort-Object)
    $count = $sorted.Length
    $rank = [int][Math]::Ceiling(($percentile / 100.0) * $count) - 1
    if ($rank -lt 0) {
        $rank = 0
    }
    if ($rank -ge $count) {
        $rank = $count - 1
    }
    return [double]$sorted[$rank]
}

function Format-Invariant([double]$value) {
    return [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:F3}", $value)
}

$tests = @(
    [PSCustomObject]@{ Name = "e2e-play-keepalive-vanilla-modern-matrix.ps1"; PortOffset = 0 },
    [PSCustomObject]@{ Name = "e2e-play-bootstrap-protocol-vanilla-modern-matrix.ps1"; PortOffset = 20 },
    [PSCustomObject]@{ Name = "e2e-play-movement-vanilla-modern-matrix.ps1"; PortOffset = 40 },
    [PSCustomObject]@{ Name = "e2e-play-input-response-vanilla-modern-matrix.ps1"; PortOffset = 70 },
    [PSCustomObject]@{ Name = "e2e-play-world-modern-matrix.ps1"; PortOffset = 90 },
    [PSCustomObject]@{ Name = "e2e-play-entity-inventory-modern-matrix.ps1"; PortOffset = 110 },
    [PSCustomObject]@{ Name = "e2e-play-combat-modern-matrix.ps1"; PortOffset = 130 },
    [PSCustomObject]@{ Name = "e2e-play-combat-lifecycle-modern-matrix.ps1"; PortOffset = 150 },
    [PSCustomObject]@{ Name = "e2e-play-extensions-vanilla-modern-matrix.ps1"; PortOffset = 170 }
)

$selectedTests = @($tests)
if ($OnlyTests.Count -gt 0) {
    $selectedTests = @()
    foreach ($name in $OnlyTests) {
        $match = $tests | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if ($null -eq $match) {
            throw "Unknown benchmark test name: $name"
        }
        $selectedTests += $match
    }
}

$timingsByTest = @{}
foreach ($test in $selectedTests) {
    $timingsByTest[$test.Name] = New-Object System.Collections.Generic.List[double]
}
$runRows = New-Object System.Collections.Generic.List[object]
$started = Get-Date

Write-Host "[ONYX][BENCH] START iterations=$Iterations tests=$($selectedTests.Count)"

for ($iteration = 0; $iteration -lt $Iterations; $iteration++) {
    Write-Host "[ONYX][BENCH] ITERATION_START index=$($iteration + 1)/$Iterations"
    $iterBasePort = $BaseBackendPort + ($iteration * $PortStridePerIteration)

    foreach ($test in $selectedTests) {
        $path = Join-Path $PSScriptRoot $test.Name
        if (-not (Test-Path $path)) {
            throw "Missing benchmark test script: $path"
        }

        $backendPort = $iterBasePort + $test.PortOffset
        $attemptPort = $backendPort
        $attempt = 0
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        while ($true) {
            $attempt++
            try {
                & $path `
                    -JavaBinary $JavaBinary `
                    -DistPath $DistPath `
                    -BaseBackendPort $attemptPort
                break
            } catch {
                $message = $_.Exception.Message
                $bindConflict = ($message -match 'Address already in use') -or ($message -match 'BindException')
                if ($bindConflict -and $attempt -lt $MaxAttemptsPerTest) {
                    $attemptPort += $RetryPortBump
                    Write-Host "[ONYX][BENCH] RETRY test=$($test.Name) attempt=$attempt reason=bind-conflict next-port=$attemptPort"
                    continue
                }
                throw "Benchmark failed at iteration=$($iteration + 1), test=$($test.Name), attempt=$attempt, base-port=${attemptPort}: $message"
            }
        }
        $sw.Stop()

        $elapsedSeconds = [Math]::Round($sw.Elapsed.TotalSeconds, 3)
        $timingsByTest[$test.Name].Add($elapsedSeconds)
        $runRows.Add([PSCustomObject]@{
            test = $test.Name
            iteration = $iteration + 1
            backend_port = $attemptPort
            elapsed_seconds = Format-Invariant -value $elapsedSeconds
        }) | Out-Null

        Write-Host "[ONYX][BENCH] RUN_OK test=$($test.Name) elapsed_seconds=$(Format-Invariant -value $elapsedSeconds) port=$attemptPort attempts=$attempt"
        if ($DelayMsBetweenRuns -gt 0) {
            Start-Sleep -Milliseconds $DelayMsBetweenRuns
        }
    }

    Write-Host "[ONYX][BENCH] ITERATION_OK index=$($iteration + 1)/$Iterations"
}

Write-Host "[ONYX][BENCH] SUMMARY_START"
foreach ($test in $tests) {
    if (-not $timingsByTest.ContainsKey($test.Name)) {
        continue
    }
    $values = @($timingsByTest[$test.Name].ToArray())
    $runs = $values.Count
    $avg = [double]($values | Measure-Object -Average).Average
    $min = [double]($values | Measure-Object -Minimum).Minimum
    $max = [double]($values | Measure-Object -Maximum).Maximum
    $p50 = Get-Percentile -values $values -percentile 50
    $p95 = Get-Percentile -values $values -percentile 95
    $p99 = Get-Percentile -values $values -percentile 99

    Write-Host ("[ONYX][BENCH] test={0} runs={1} avg={2} p50={3} p95={4} p99={5} min={6} max={7}" -f `
        $test.Name, $runs, (Format-Invariant -value $avg), (Format-Invariant -value $p50), (Format-Invariant -value $p95), (Format-Invariant -value $p99), (Format-Invariant -value $min), (Format-Invariant -value $max))
}

if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
    $root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    $reportFullPath = if ([System.IO.Path]::IsPathRooted($ReportPath)) { $ReportPath } else { Join-Path $root $ReportPath }
    $reportDir = Split-Path -Parent $reportFullPath
    if (-not [string]::IsNullOrWhiteSpace($reportDir)) {
        New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    }
    $runRows | Export-Csv -Path $reportFullPath -NoTypeInformation -Encoding UTF8
    Write-Host "[ONYX][BENCH] REPORT=$reportFullPath"
}

$elapsedTotal = [int][Math]::Round(((Get-Date) - $started).TotalSeconds)
Write-Host "[ONYX] E2E_PLAY_BENCHMARK_OK"
Write-Host "[ONYX][BENCH] ELAPSED_SECONDS=$elapsedTotal"
