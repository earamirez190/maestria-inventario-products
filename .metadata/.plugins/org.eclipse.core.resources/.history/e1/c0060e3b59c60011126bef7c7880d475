param(
    [int]$Vus = 50,
    [string]$Duration = '1m',
    [string]$BaseUrl = 'http://maestria-observabilidad-alb-588169902.us-east-1.elb.amazonaws.com',
    [string]$AwsExe = 'C:\Program Files\Amazon\AWSCLIV2\aws.exe',
    [string]$ClusterName = 'maestria-observabilidad-cluster',
    [string]$ServiceName = 'maestria-observabilidad-service'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$resultsDir = Join-Path $repoRoot 'benchmark/results/aws'
New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null

if (-not (Test-Path $AwsExe)) { throw "No se encontró AWS CLI en $AwsExe" }
$k6 = (Get-Command k6 -ErrorAction Stop).Source
$scriptPath = Join-Path $repoRoot 'benchmark/k6-products-read.js'
$safeBaseUrl = $BaseUrl.TrimEnd('/')
$runId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$summaryPath = Join-Path $resultsDir "k6-products-read-$runId.json"
$resultPath = Join-Path $resultsDir "summary-$runId.json"

$start = (Get-Date).ToUniversalTime()
Write-Host "Benchmark AWS: $safeBaseUrl/api/products"
Write-Host "Configuración: VUs=$Vus, duración=$Duration, solo lectura"

$arguments = @(
    'run',
    '--summary-trend-stats=p(50),p(95),p(99),avg,min,max',
    "--summary-export=`"$summaryPath`"",
    "-e=BASE_URL=$safeBaseUrl",
    "-e=VUS=$Vus",
    "-e=DURATION=$Duration",
    "`"$scriptPath`""
)
$process = Start-Process -FilePath $k6 -ArgumentList ($arguments -join ' ') -NoNewWindow -PassThru
$process.WaitForExit()
if ($process.ExitCode -ne 0) { throw "k6 terminó con código $($process.ExitCode)." }
$end = (Get-Date).ToUniversalTime()

$summary = Get-Content -Raw $summaryPath | ConvertFrom-Json
$durationMetric = $summary.metrics.http_req_duration
$failedMetric = $summary.metrics.http_req_failed
$checksMetric = $summary.metrics.checks
$requestsMetric = $summary.metrics.http_reqs

$result = [ordered]@{
    runId = $runId
    target = "$safeBaseUrl/api/products"
    workload = 'GET /api/products'
    otelMode = 'enabled-in-production'
    vus = $Vus
    duration = $Duration
    startUtc = $start.ToString('o')
    endUtc = $end.ToString('o')
    requests = [math]::Round([double]$requestsMetric.count, 0)
    requestsPerSecond = [math]::Round([double]$requestsMetric.rate, 3)
    failedRatePercent = [math]::Round(([double]$failedMetric.value) * 100, 3)
    checksRatePercent = [math]::Round(([double]$checksMetric.value) * 100, 3)
    p50Ms = [math]::Round([double]$durationMetric.'p(50)', 3)
    p95Ms = [math]::Round([double]$durationMetric.'p(95)', 3)
    p99Ms = [math]::Round([double]$durationMetric.'p(99)', 3)
}

$result | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 -Path $resultPath
Write-Host ($result | ConvertTo-Json -Depth 5)
Write-Host "Resultado guardado en $resultPath"
