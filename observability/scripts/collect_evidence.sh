#!/usr/bin/env bash
set -euo pipefail

# collect_evidence.sh
# Recopila evidencias automáticas para el laboratorio de observabilidad.
# Guarda resultados en ./evidence/{local,gcp,aws,chaos} según corresponda.

ROOT_DIR=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
EVIDENCE_DIR="$ROOT_DIR/evidence"
LOCAL_DIR="$EVIDENCE_DIR/local"
CHAOS_DIR="$EVIDENCE_DIR/chaos"
GCP_DIR="$EVIDENCE_DIR/gcp"
AWS_DIR="$EVIDENCE_DIR/aws"

mkdir -p "$LOCAL_DIR" "$CHAOS_DIR" "$GCP_DIR" "$AWS_DIR"
TS=$(date -u +"%Y%m%dT%H%M%SZ")
RUN_PREFIX="run_$TS"

echo "Collecting evidences into $EVIDENCE_DIR (timestamp: $TS)"

# Helper: run curl and write output
curl_save() {
  local url="$1"; local out="$2"; local auth="${3:-}";
  if [ -n "$auth" ]; then
    curl -sS -u "$auth" "$url" -o "$out" || echo "curl failed for $url" >&2
  else
    curl -sS "$url" -o "$out" || echo "curl failed for $url" >&2
  fi
}

# 1) Health checks
echo "- Health checks"
if curl -sS http://localhost:9092/health -o /dev/null; then
  curl -sS http://localhost:9092/health | jq . > "$LOCAL_DIR/app_health_$TS.json" || true
else
  echo "WARNING: app health endpoint not reachable at http://localhost:9092/health" >&2
fi

if curl -sS http://localhost:8002/health -o /dev/null; then
  curl -sS http://localhost:8002/health | jq . > "$LOCAL_DIR/data_service_health_$TS.json" || true
else
  echo "WARNING: data-service health endpoint not reachable at http://localhost:8002/health" >&2
fi

# 2) API call that includes trace_id
echo "- Calling data-service /data/products"
DATA_PRODUCTS_OUT="$LOCAL_DIR/data_products_$TS.json"
if curl -sS "http://localhost:9092/api/observability/data/products" -o "$DATA_PRODUCTS_OUT"; then
  echo "Saved $DATA_PRODUCTS_OUT"
  TRACE_ID=$(jq -r '.trace_id // empty' "$DATA_PRODUCTS_OUT" || true)
  if [ -n "$TRACE_ID" ]; then
    echo "$TRACE_ID" > "$LOCAL_DIR/trace_id_$TS.txt"
    echo "Found trace_id: $TRACE_ID"
    # Try to fetch Jaeger trace (if available)
    echo "http://localhost:16686/trace/$TRACE_ID" > "$LOCAL_DIR/jaeger_trace_link_$TS.txt"
  else
    echo "No trace_id found in API response" >&2
  fi
else
  echo "WARNING: request to data-service failed" >&2
fi

# 3) Prometheus queries (p99 latency example)
echo "- Querying Prometheus (p99 latency)"
PROM_OUT="$LOCAL_DIR/prometheus_p99_$TS.json"
if curl -sG 'http://localhost:9093/api/v1/query' --data-urlencode 'query=histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))' -o "$PROM_OUT"; then
  jq . "$PROM_OUT" > "$PROM_OUT" || true
  echo "Saved $PROM_OUT"
else
  echo "Prometheus not reachable at http://localhost:9093 (skipping)" >&2
fi

# 4) Grafana export (Golden Signals)
echo "- Exporting Grafana dashboard (Golden Signals) if available"
if [ -n "${GRAFANA_USER-}" ] && [ -n "${GRAFANA_PASS-}" ]; then
  DASH_SEARCH=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASS" "http://localhost:3002/api/search?query=Golden%20Signals" || true)
  DASH_UID=$(echo "$DASH_SEARCH" | jq -r '.[0].uid // empty' || true)
  if [ -n "$DASH_UID" ]; then
    curl -s -u "$GRAFANA_USER:$GRAFANA_PASS" "http://localhost:3002/api/dashboards/uid/$DASH_UID" | jq . > "$LOCAL_DIR/grafana_golden_signals_$TS.json" || true
    echo "Saved Grafana dashboard to $LOCAL_DIR/grafana_golden_signals_$TS.json"
  else
    echo "Golden Signals dashboard not found in Grafana (search returned empty)" >&2
  fi
else
  echo "GRAFANA_USER/GRAFANA_PASS not set; skipping Grafana export" >&2
fi

# 5) Container logs for data-service (last 5m)
echo "- Collecting container logs for data-service"
DS_CONT=$(docker ps --filter "name=data-service" -q || true)
if [ -n "$DS_CONT" ]; then
  docker logs --since 5m $DS_CONT 2>&1 | tail -n 1000 > "$LOCAL_DIR/data_service_logs_$TS.txt" || true
  echo "Saved container logs to $LOCAL_DIR/data_service_logs_$TS.txt"
else
  echo "No running container named data-service found" >&2
fi

# 6) Prometheus alerts (Alertmanager)
echo "- Saving current alerts from Alertmanager/Prometheus"
if curl -s http://localhost:9093/api/v1/alerts -o "$LOCAL_DIR/alerts_$TS.json"; then
  echo "Saved alerts to $LOCAL_DIR/alerts_$TS.json"
else
  echo "Alertmanager not reachable at http://localhost:9093 (skipping)" >&2
fi

# 7) Chaos scripts output (run them optionally)
echo "- (Optional) Running chaos scripts is manual; existing scripts are in observability/chaos/"
# We don't run chaos automatically to avoid injecting faults accidentalmente.
# If user wants to run, they can execute:
# bash observability/chaos/latency-injection.sh <URL> <ms>
# bash observability/chaos/error-injection.sh <URL>

# 8) GCP / AWS quick snapshots (if CLIs present and authenticated)
if command -v gcloud >/dev/null 2>&1 && [ -n "${GCP_PROJECT-}" ]; then
  echo "- Capturing GCP sample logs (requires permissions)"
  gcloud config set project "$GCP_PROJECT" >/dev/null 2>&1 || true
  gcloud logging read 'resource.type="gce_subnetwork"' --limit 50 --format=json > "$GCP_DIR/gcp_logging_sample_$TS.json" || true
  echo "Saved GCP logging sample to $GCP_DIR/gcp_logging_sample_$TS.json"
else
  echo "gcloud not available or GCP_PROJECT not set; skipping GCP snapshots" >&2
fi

if command -v aws >/dev/null 2>&1 && [ -n "${AWS_ACCOUNT_ID-}" ]; then
  echo "- Capturing AWS sample (requires permissions)"
  aws logs describe-log-groups --limit 10 --region "${AWS_REGION:-us-east-1}" > "$AWS_DIR/aws_log_groups_$TS.json" || true
  echo "Saved AWS log groups to $AWS_DIR/aws_log_groups_$TS.json"
else
  echo "aws CLI not available or AWS_ACCOUNT_ID not set; skipping AWS snapshots" >&2
fi

# 9) Pack summary
SUMMARY="$EVIDENCE_DIR/summary_$TS.txt"
cat > "$SUMMARY" <<EOF
Evidence run: $TS
Local evidence: $LOCAL_DIR
Chaos evidence: $CHAOS_DIR
GCP evidence: $GCP_DIR
AWS evidence: $AWS_DIR
Trace captured: ${TRACE_ID:-none}
EOF

echo "Finished evidence collection. Summary: $SUMMARY"

exit 0
