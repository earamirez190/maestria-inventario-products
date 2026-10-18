$ErrorActionPreference = "Stop"
$PROM_HOST = "http://localhost:9093"
$APP_HOST = "http://localhost:9092"
$SERVICEB_HOST = "http://localhost:9094"
$EvidenceDir = Join-Path (Get-Location) "evidence"
New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null

function Invoke-PromQuery {
    param(
        [string]$Query
    )

    $raw = curl.exe -sS -G --data-urlencode "query=$Query" "$PROM_HOST/api/v1/query"
    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    try {
        $json = $raw | ConvertFrom-Json
        if ($json -and $json.data -and $json.data.result -and $json.data.result.Count -gt 0) {
            return $json.data.result[0].value[1]
        }
        return $null
    }
    catch {
        return $null
    }
}

Write-Host "1) Starting docker compose..."
docker compose up -d --build

Write-Host "2) Waiting for app and service-b to be healthy..."
$timeoutSeconds = 300
$deadline = (Get-Date).AddSeconds($timeoutSeconds)

while ($true) {
    $appHealth = docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-health{{end}}' inventario-products-app 2>$null
    $svcHealth = docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-health{{end}}' inventario-audit-service 2>$null

    Write-Host "   app=$appHealth | service-b=$svcHealth"

    if ($appHealth -eq "healthy" -and $svcHealth -eq "healthy") {
        break
    }

    if ((Get-Date) -gt $deadline) {
        Write-Host "Timeout waiting for health; continuing anyway."
        break
    }

    Start-Sleep -Seconds 5
}

Write-Host ""
Write-Host "3) Saving Prometheus targets to evidence/prometheus_targets.json"
curl.exe -sS "$PROM_HOST/api/v1/targets" > (Join-Path $EvidenceDir "prometheus_targets.json")

Write-Host "4) Saving /actuator/prometheus output from app and service-b"
curl.exe -sS "$APP_HOST/actuator/prometheus" | Select-Object -First 80 | Set-Content (Join-Path $EvidenceDir "app_prometheus.txt")
curl.exe -sS "$SERVICEB_HOST/actuator/prometheus" | Select-Object -First 80 | Set-Content (Join-Path $EvidenceDir "serviceb_prometheus.txt")

Write-Host "Waiting 30s for Prometheus to scrape..."
Start-Sleep -Seconds 30

Write-Host ""
Write-Host "5) Detecting histogram metric..."
$histCandidates = @(
    "http_request_duration_seconds_bucket",
    "http_server_requests_seconds_bucket",
    "http_server_request_duration_seconds_bucket"
)

$histMetric = $null
foreach ($m in $histCandidates) {
    $val = Invoke-PromQuery "count($m)"
    if ($val -and $val -ne "0" -and $val -ne "N/A") {
        $histMetric = $m
        break
    }
}

if (-not $histMetric) {
    Write-Host "No histogram found among:"
    $histCandidates | ForEach-Object { Write-Host "   $_" }
    Write-Host ""
    Write-Host "Check the exported metrics in evidence/app_prometheus.txt and evidence/serviceb_prometheus.txt"
    exit 0
}

Write-Host "Using histogram metric: $histMetric"

$p50 = Invoke-PromQuery "histogram_quantile(0.50, sum(rate($histMetric[5m])) by (le))"
$p95 = Invoke-PromQuery "histogram_quantile(0.95, sum(rate($histMetric[5m])) by (le))"
$p99 = Invoke-PromQuery "histogram_quantile(0.99, sum(rate($histMetric[5m])) by (le))"

Write-Host "p50 latency: $p50"
Write-Host "p95 latency: $p95"
Write-Host "p99 latency: $p99"

Write-Host ""
Write-Host "6) Detecting count metric for RPS and error rate..."
$countCandidates = @(
    "http_request_duration_seconds_count",
    "http_server_requests_seconds_count",
    "http_server_request_duration_seconds_count"
)

$countMetric = $null
foreach ($m in $countCandidates) {
    $val = Invoke-PromQuery "count($m)"
    if ($val -and $val -ne "0" -and $val -ne "N/A") {
        $countMetric = $m
        break
    }
}

if ($countMetric) {
    $rps = Invoke-PromQuery "sum(rate($countMetric[5m]))"
    $errorRate = Invoke-PromQuery "100 * (sum(rate($countMetric{status!~`"2..`"}[5m])) / sum(rate($countMetric[5m])))"
    Write-Host "RPS: $rps"
    Write-Host "Error rate %: $errorRate"
} else {
    Write-Host "No count metric found. Check metric names in evidence/*.txt"
}

Write-Host ""
Write-Host "7) Optional CPU / memory checks (works if container metrics are present)"
$cpu = Invoke-PromQuery "sum(rate(container_cpu_usage_seconds_total[5m])) * 100"
$mem = Invoke-PromQuery "sum(container_memory_working_set_bytes) / 1024 / 1024"

if ($cpu) { Write-Host "CPU %: $cpu" } else { Write-Host "CPU metric not available" }
if ($mem) { Write-Host "Memory MB: $mem" } else { Write-Host "Memory metric not available" }

Write-Host ""
Write-Host "Done."
Write-Host "Evidence saved in: $EvidenceDir"
Write-Host "Prometheus UI: http://localhost:9093"
Write-Host "App health: http://localhost:9092/actuator/health"
Write-Host "Audit health: http://localhost:9094/actuator/health"