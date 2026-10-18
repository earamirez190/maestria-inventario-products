#!/usr/bin/env bash
set -euo pipefail

# Módulo C. Ejecutar únicamente en un proyecto sandbox propio.
PROJECT_ID=${PROJECT_ID:?"Define PROJECT_ID"}
REGION=${REGION:-us-central1}
SUBNET=${SUBNET:-default}

echo "This script changes GCP networking/security resources in $PROJECT_ID."
echo "Run with APPLY=1 only after reviewing the project and billing scope."

if [[ "${APPLY:-0}" != "1" ]]; then
  echo "Would enable: securitycenter.googleapis.com logging.googleapis.com"
  echo "Would update subnet: gcloud compute networks subnets update $SUBNET --region $REGION --project $PROJECT_ID --enable-flow-logs"
  exit 0
fi

gcloud services enable securitycenter.googleapis.com logging.googleapis.com \
  --project "$PROJECT_ID"
gcloud compute networks subnets update "$SUBNET" \
  --region "$REGION" --project "$PROJECT_ID" --enable-flow-logs

cat <<'EOF'
Flow Logs enabled. Next create a Cloud Logging metric for rejected traffic,
then connect it to a Monitoring alert and the security dashboard.
Security Command Center findings require the edition and organization-level
permissions configured by the project administrator.
EOF
