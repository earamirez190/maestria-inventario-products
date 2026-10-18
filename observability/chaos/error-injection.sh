#!/usr/bin/env bash
set -euo pipefail

# Experimento D2: 10% de errores en data-service.
# La tasa se aplica en el servicio y se restaura a 0 al salir.
ROOT_DIR=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
URL=${1:-http://localhost:9092/api/observability/data/products}
REQUESTS=${2:-100}
START=$(date -u +%Y-%m-%dT%H:%M:%SZ)

cleanup() {
  CHAOS_ERROR_RATE=0 docker compose -f "$ROOT_DIR/docker-compose.yml" up -d --force-recreate data-service >/dev/null
}
trap cleanup EXIT

CHAOS_ERROR_RATE=0.10 docker compose -f "$ROOT_DIR/docker-compose.yml" up -d --force-recreate data-service >/dev/null
sleep 5

echo "experiment=data-service-error-rate-10pct"
echo "started_at=$START"
echo "url=$URL"
echo "requests=$REQUESTS"
echo "timestamp,http_code,time_total"
for _ in $(seq 1 "$REQUESTS"); do
  date -u +%Y-%m-%dT%H:%M:%SZ | tr '\n' ','
  curl -sS -o /dev/null -w '%{http_code},%{time_total}\n' "$URL" || echo '000,failed'
done
echo "finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
