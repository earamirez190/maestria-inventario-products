#!/usr/bin/env bash
set -euo pipefail

# Experimento D1: +200 ms en el cliente de service-b.
# Se reinicia únicamente el contenedor local service-b y se restaura a 0 al final.
ROOT_DIR=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
URL=${1:-http://localhost:9092/api/observability/data/products}
REQUESTS=${2:-20}
START=$(date -u +%Y-%m-%dT%H:%M:%SZ)

cleanup() {
  CHAOS_LATENCY_MS=0 docker compose -f "$ROOT_DIR/docker-compose.yml" up -d --force-recreate service-b >/dev/null
}
trap cleanup EXIT

CHAOS_LATENCY_MS=200 docker compose -f "$ROOT_DIR/docker-compose.yml" up -d --force-recreate service-b >/dev/null
sleep 5

echo "experiment=service-b-latency-200ms"
echo "started_at=$START"
echo "url=$URL"
echo "requests=$REQUESTS"
echo "timestamp,http_code,time_total"
for _ in $(seq 1 "$REQUESTS"); do
  date -u +%Y-%m-%dT%H:%M:%SZ | tr '\n' ','
  curl -sS -o /dev/null -w '%{http_code},%{time_total}\n' "$URL" || echo '000,failed'
done
echo "finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
