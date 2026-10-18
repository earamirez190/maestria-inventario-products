param(
    [int]$Vus = 50,
    [string]$Duration = '1m',
    [string]$BaseUrl = 'http://localhost:9092'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$resultsDir = Join-Path $repoRoot 'benchmark/results'
New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null

function Wait-Healthy {
    param([string]$ContainerName)

    for ($attempt = 1; $attempt -le 60; $attempt++) {
        $status = docker inspect --format='{{.State.Health.Status}}' $ContainerName 2>$null
        if ($status -eq 'healthy') { return }
        Start-Sleep -Seconds 2
    }
    throw "El contenedor $ContainerName no llegó a healthy."
}

function Convert-MemoryToMiB {
    param([string]$Value)
    if ($Value -notmatch '([0-9]+(?:\.[0-9]+)?)\s*([A-Za-z]+)') { return $null }
    $number = [double]$Matches[1]
    switch -Regex ($Matches[2]) {
        '^KiB$' { return $number / 1024 }
        '^MiB$' { return $number }
        '^GiB$' { return $number * 1024 }
        '^KB$' { return $number / 1000 }
        '^MB$' { return $number }
        '^GB$' { return $number * 1000 }
        default { return $number }
    }
}

function Invoke-ModeBenchmark {
    param(
        [string]$Mode,
        [bool]$OtelDisabled
    )

    $env:OTEL_SDK_DISABLED = if ($OtelDisabled) { 'true' } else { 'false' }
    Write-Host "`n=== Benchmark $Mode (OTEL_SDK_DISABLED=$env:OTEL_SDK_DISABLED) ==="
    docker compose up -d --force-recreate app service-b | Out-Host
    Wait-Healthy 'inventario-products-app'
    Wait-Healthy 'inventario-audit-service'

    $summaryPath = Join-Path $resultsDir "k6-$Mode.json"
    $samplesPath = Join-Path $resultsDir "docker-stats-$Mode.csv"
    Set-Content -Path $samplesPath -Value 'Timestamp;Name;CpuPercent;MemUsage'

    $k6 = (Get-Command k6 -ErrorAction Stop).Source
    $scriptPath = Join-Path $repoRoot 'benchmark/k6-products.js'
    $arguments = @(
        'run',
        '--summary-trend-stats=p(50),p(95),p(99),avg,min,max',
        "`"--summary-export=$summaryPath`"",
        "-e=BASE_URL=$BaseUrl",
        "-e=VUS=$Vus",
        "-e=DURATION=$Duration",
        "`"$scriptPath`""
    )
    $process = Start-Process -FilePath $k6 -ArgumentList ($arguments -join ' ') -NoNewWindow -PassThru

    while (-not $process.HasExited) {
        $timestamp = (Get-Date).ToString('o')
        docker stats --no-stream --format '{{.Name}};{{.CPUPerc}};{{.MemUsage}}' |
            Where-Object { $_ -match '^(inventario-products-app|inventario-audit-service);' } |
            ForEach-Object {
                $parts = $_ -split ';', 3
                $cpu = $parts[1] -replace '%', ''
                Add-Content -Path $samplesPath -Value "$timestamp;$($parts[0]);$cpu;$($parts[2])"
            }
        Start-Sleep -Seconds 5
    }
    $process.WaitForExit()
    $process.Refresh()
    if ($null -ne $process.ExitCode -and $process.ExitCode -ne 0) { throw "k6 falló en el modo $Mode con código $($process.ExitCode)." }

    $summary = Get-Content -Raw $summaryPath | ConvertFrom-Json
    $durationMetric = $summary.metrics.http_req_duration
    $failedMetric = $summary.metrics.http_req_failed
    $checksMetric = $summary.metrics.checks
    $requestsMetric = $summary.metrics.http_reqs
    $samples = Import-Csv -Delimiter ';' -Path $samplesPath

    $result = [ordered]@{
        mode = $Mode
        otelSdkDisabled = $OtelDisabled
        vus = $Vus
        duration = $Duration
        requests = [math]::Round([double]$requestsMetric.count, 0)
        requestsPerSecond = [math]::Round([double]$requestsMetric.rate, 3)
        failedRatePercent = [math]::Round(([double]$failedMetric.value) * 100, 3)
        checksRatePercent = [math]::Round(([double]$checksMetric.value) * 100, 3)
        p50Ms = [math]::Round([double]$durationMetric.'p(50)', 3)
        p95Ms = [math]::Round([double]$durationMetric.'p(95)', 3)
        p99Ms = [math]::Round([double]$durationMetric.'p(99)', 3)
    }

    foreach ($container in @('inventario-products-app', 'inventario-audit-service')) {
        $containerSamples = @($samples | Where-Object { $_.Name -eq $container })
        $cpuValues = @($containerSamples | ForEach-Object { [double]$_.CpuPercent })
        $memoryValues = @($containerSamples | ForEach-Object { Convert-MemoryToMiB $_.MemUsage.Split('/')[0].Trim() })
        $safeName = if ($container -eq 'inventario-products-app') { 'app' } else { 'audit' }
        $result["${safeName}CpuAvgPercent"] = if ($cpuValues.Count) { [math]::Round(($cpuValues | Measure-Object -Average).Average, 3) } else { $null }
        $result["${safeName}CpuMaxPercent"] = if ($cpuValues.Count) { [math]::Round(($cpuValues | Measure-Object -Maximum).Maximum, 3) } else { $null }
        $result["${safeName}MemoryAvgMiB"] = if ($memoryValues.Count) { [math]::Round(($memoryValues | Measure-Object -Average).Average, 3) } else { $null }
        $result["${safeName}MemoryMaxMiB"] = if ($memoryValues.Count) { [math]::Round(($memoryValues | Measure-Object -Maximum).Maximum, 3) } else { $null }
    }

    [pscustomobject]$result
}

$results = @(
    Invoke-ModeBenchmark -Mode 'without-otel' -OtelDisabled $true
    Invoke-ModeBenchmark -Mode 'with-otel' -OtelDisabled $false
)

$results | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $resultsDir 'summary.json')
$results | Export-Csv -NoTypeInformation -Path (Join-Path $resultsDir 'summary.csv')
$results | Format-Table -AutoSize
Write-Host "`nResultados guardados en $resultsDir"
