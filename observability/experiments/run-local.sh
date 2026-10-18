#!/usr/bin/env bash
set -euo pipefail

# Ejecuta los dos experimentos del Módulo D en un entorno Docker local.
# No debe ejecutarse contra una URL de producción ni contra un namespace compartido.

ROOT_DIR=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
URL=${URL:-http://localhost:9092/api/observability/data/products}
REQUESTS=${REQUESTS:-60}
OUT_DIR=${OUT_DIR:-"$ROOT_DIR/evidence/chaos/run_$(date -u +%Y%m%dT%H%M%SZ)"}

mkdir -p "$OUT_DIR"

echo "experiment_run=$OUT_DIR"
echo "url=$URL"
echo "requests=$REQUESTS"

echo "baseline_started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee "$OUT_DIR/timestamps.txt"
{
  echo "timestamp,http_code,time_total"
  for _ in $(seq 1 "$REQUESTS"); do
    date -u +%Y-%m-%dT%H:%M:%SZ | tr '\n' ','
    curl -sS -o /dev/null -w '%{http_code},%{time_total}\n' "$URL" || echo '000,failed'
  done
} > "$OUT_DIR/baseline.csv"
echo "baseline_finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee -a "$OUT_DIR/timestamps.txt"

bash "$ROOT_DIR/observability/chaos/latency-injection.sh" "$URL" "$REQUESTS" \
  > "$OUT_DIR/latency-200ms.csv"
bash "$ROOT_DIR/observability/chaos/error-injection.sh" "$URL" "$REQUESTS" \
  > "$OUT_DIR/error-rate-10pct.csv"

curl -sS http://localhost:9093/api/v1/alerts > "$OUT_DIR/prometheus-alerts.json" || true
curl -sS http://localhost:9464/metrics > "$OUT_DIR/otel-prometheus-metrics.txt" || true
curl -sS http://localhost:9092/actuator/prometheus > "$OUT_DIR/app-metrics.txt" || true

python3 "$ROOT_DIR/observability/experiments/summarize-results.py" \
  "$OUT_DIR" > "$OUT_DIR/summary.json"

echo "Evidence saved in $OUT_DIR"
