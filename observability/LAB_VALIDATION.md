# Validación del laboratorio — Data Service y Observability

Este documento explica cómo verificar (local, GCP y AWS) que la extensión con el microservicio "data-service" y la solución de observabilidad (OTel + Collector + Prometheus/Grafana/Loki/Jaeger) funcionan, y qué evidencias capturar para cada módulo (A–E).

IMPORTANTE: Ejecuta los comandos desde la raíz del repositorio clonado en la rama `develop-taller-gcp`.

Requisitos previos
- Git y haber hecho checkout a la rama develop-taller-gcp:
  - git fetch origin
  - git checkout develop-taller-gcp
- Docker & Docker Compose (v2) para pruebas locales
- jq, curl, wget
- Python 3.11+ (solo si necesitas correr scripts locales fuera de Docker)
- gcloud CLI (autenticado) para GCP
- aws CLI (autenticado) para AWS

Estructura de evidencia que se recogerá
- Respuestas HTTP (JSON) de endpoints /health y /data/* con trace_id
- Traces en Jaeger (link + trace_id) o exported trace JSON
- Capturas (JSON/PNG) de dashboards de Grafana
- Export de métricas de Prometheus (consulta y CSV/JSON)
- Logs estructurados con trace_id (colección en Loki o archivo JSON)
- Resultados del experimento de chaos (tiempos, errores, alertas disparadas)
- Alertas de AIOps / Anomalia (pruebas comparativas: umbrales estáticos vs AIOps)
- Reporte final observability/maturity/report.md completado con links a evidencias

1) Validación local (Docker Compose)
Objetivo: Levantar el stack completo localmente, generar trazas y métricas, ejecutar chaos y recolectar evidencias.

Comandos básicos:

# Levantar stack
docker compose up -d --build

# Esperar servicios y comprobar health
# Service principal expuesto en el docker-compose como app o data-service según el compose
curl -sS http://localhost:9092/health | jq . > evidence/local-health-app.json
curl -sS http://localhost:8000/health | jq . > evidence/local-health-data-service.json

Si el endpoint expone trace_id (data-service lo hace):
curl -sS "http://localhost:8000/data/products" | jq . > evidence/local-data-products.json
# Extrae trace_id
jq -r '.trace_id' evidence/local-data-products.json > evidence/trace_id.txt

# Verificar métricas Prometheus (ejemplo p99 latency)
curl -sG 'http://localhost:9093/api/v1/query' --data-urlencode 'query=histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))' | jq . > evidence/prometheus_p99.json

# Exportar dashboard Grafana a JSON (si Grafana está en localhost:3000 y tienes credenciales)
# Configurar variables GRAFANA_USER y GRAFANA_PASS
export GRAFANA_USER=admin
export GRAFANA_PASS=admin
DASH_UID=$(curl -s -u $GRAFANA_USER:$GRAFANA_PASS "http://localhost:3000/api/search?query=Golden%20Signals" | jq -r '.[0].uid')
curl -s -u $GRAFANA_USER:$GRAFANA_PASS "http://localhost:3000/api/dashboards/uid/$DASH_UID" | jq . > evidence/grafana_golden_signals.json

# Buscar la traza en Jaeger (si Jaeger UI está en http://localhost:16686)
TRACE_ID=$(cat evidence/trace_id.txt)
echo "Trace URL: http://localhost:16686/search?tags=%7B%7D&service=data-service&traceID=$TRACE_ID" > evidence/jaeger_trace_link.txt

# Recolectar logs JSON (si Loki o salida estándar captura logs). Ejemplo: guardar últimos 200 logs del contenedor data-service
docker logs --since 5m $(docker ps --filter "name=data-service" -q) 2>&1 | tail -n 500 > evidence/data-service-logs.txt

# Ejecutar chaos experiments (local)
# 1) Latency injection en service-b (200ms): usar el script que ya está en observability/chaos/latency-injection.sh
bash observability/chaos/latency-injection.sh http://localhost:9092/api/products 200
# 2) Error injection 10% en data-service
bash observability/chaos/error-injection.sh http://localhost:8000/data/products

# Ejecutar benchmark k6 si quieres reproducir carga (requiere k6 instalado)
./benchmark/run-benchmark.ps1

Evidencias a guardar en carpeta evidence/local/:
- local-health-app.json
- local-health-data-service.json
- local-data-products.json
- prometheus_p99.json
- grafana_golden_signals.json
- jaeger_trace_link.txt
- data-service-logs.txt
- chaos-result-*.txt (salida de los scripts)

2) Módulo A — Instrumentación completa y spans DB (local & nube)
Comprobaciones locales:
- Ver que /data/products devuelve trace_id (ya incluido en data-service)
- Ver atributos OTel DB en el span (db.system, db.statement, db.operation). Para esto extrae la traza desde Jaeger API:
JAEGER_QUERY_API=http://localhost:16686/api/traces/$TRACE_ID
curl -s "$JAEGER_QUERY_API" | jq . > evidence/jaeger_trace_$TRACE_ID.json
# Busca atributos db.system y db.statement
jq '..|.tags? // empty | .[]? | select(.key == "db.system" or .key=="db.statement")' evidence/jaeger_trace_$TRACE_ID.json > evidence/jaeger_db_tags.json

En GCP (Cloud SQL) — pasos resumidos:
# 1. Habilitar APIs
gcloud services enable container.googleapis.com sqladmin.googleapis.com artifactregistry.googleapis.com

# 2. Crear Cloud SQL Postgres (o MySQL según tu código). Ejemplo Postgres:
gcloud sql instances create lab-sql --database-version=POSTGRES_14 --tier=db-f1-micro --region=us-central1
# crear user y db
gcloud sql users set-password postgres --instance=lab-sql --password="MySecret123"

# 3. Conectar desde GKE: crea secreto con la connection string
# Para Cloud SQL usando proxy o using private ip; ejemplo simple: obtener connection name
INSTANCE_CONN_NAME=$(gcloud sql instances describe lab-sql --format='value(connectionName)')
# En k8s deployment usa cloudsql-proxy sidecar o usa Cloud SQL Auth proxy

# 4. Build & push imagen a Artifact Registry y desplegar a GKE (ejemplo)
# Autenticarse en Artifact Registry
gcloud auth configure-docker us-central1-docker.pkg.dev
IMAGE=us-central1-docker.pkg.dev/YOUR_PROJECT/maestria-inventario-products/data-service:latest
docker build -t $IMAGE services/data-service
docker push $IMAGE
# Aplicar manifiestos k8s (asume k8s/ tiene manifests paramétricos)
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/data-service-deployment.yaml

# 5. Validar: same health endpoints, traces (exportadas a collector) y Prometheus scraping

En AWS (RDS + ECS Fargate) — pasos resumidos:
# 1. Crear RDS (Postgres/MySQL)
aws rds create-db-instance --db-instance-identifier lab-db --engine postgres --allocated-storage 20 --db-instance-class db.t3.micro --master-username admin --master-user-password MySecret123 --no-publicly-accessible

# 2. Build & push a ECR
aws ecr create-repository --repository-name maestria-inventario-products || true
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-1
ECR_URI=$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/maestria-inventario-products/data-service:latest
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com
docker build -t $ECR_URI services/data-service
docker push $ECR_URI

# 3. Actualizar task definition / servicio ECS Fargate para usar la nueva imagen y variables DB
# 4. Validar endpoints, traces y métricas desde los servicios en AWS

3) Módulo B — AIOps (GCP / AWS)
Objetivo: configurar detector de anomalías y regla de correlación: error_rate > baseline + 2σ Y latency_p99 > SLO_threshold → alerta con trace_id

GCP (Cloud Monitoring Anomaly Detection)
# Crear una alerta usando gcloud monitoring policies o la UI. Ejemplo con gcloud:
cat > observability/alerts/gcp-aiops-policy.json <<'EOF'
{
  "displayName": "AIOps - ErrorRate+Latency Anomaly",
  "combiner": "AND",
  "conditions": [ /* condition for error rate anomaly and p99 latency */ ]
}
EOF
# Luego crear policy
gcloud monitoring policies create --policy-from-file=observability/alerts/gcp-aiops-policy.json

Recomendación: usar Cloud Monitoring Anomaly Detection for time series (crear condition with metric type: custom.googleapis.com/http/error_rate and use MQL anomaly detection). Incluir documentation field with a runbook and instruction to include trace_id (trace linking) — en el anotación o en la payload de la alerta.

AWS (DevOps Guru / CloudWatch Anomaly Detection)
# Crear anomaly detection with CloudWatch
aws cloudwatch put-anomaly-detector --namespace "YourNamespace" --metric-name "ErrorRate" --statistic "Average" --configuration '{"ExcludedTimeRanges": []}'
# Crear alarm composite: composite alarm or alarm that triggers when both conditions met. Para enriquecer alertas con trace_id, configure el servicio que envía la alerta para incluir trace_id en el payload (AlertManager webhook o SNS message body puede contener trace_id si lo extraes del payload del request o del span).

Validación práctica (local + nube):
- Generar carga con y sin anomaly detector habilitado y comparar número de alertas en ventanas idénticas (por ejemplo 30 minutos). Guardar conteos en evidence/aiops/alerts_with_aiops.txt y evidence/aiops/alerts_static.txt
- Cada alerta debe incluir trace_id: para ello, en Alertmanager webhook o en policy documentation, asegúrate que la alerta envía el trace_id obtenido del span (si usas Prometheus Alertmanager puedes usar the label extraction from request label trace_id).

4) Módulo C — Network & Security Observability
GCP — VPC Flow Logs
# Habilitar flujo
gcloud compute networks subnets update default --region=us-central1 --enable-flow-logs
# Exportar a Cloud Logging y desde allí a BigQuery / Grafana

AWS — VPC Flow Logs
aws ec2 create-flow-logs --resource-type VPC --resource-ids vpc-xxxx --traffic-type ALL --log-destination-type cloud-watch-logs --log-destination arn:aws:logs:$REGION:$ACCOUNT_ID:log-group:/aws/vpc/flowlogs

Security Command Center / AWS Security Hub
# Habilitar SCC (GCP)
gcloud services enable securitycenter.googleapis.com
# Habilitar AWS Security Hub
aws securityhub enable-security-hub

Dashboards: Golden Signals de Seguridad
- Ya existe observability/dashboards/golden-signals-security.json
- Para exportar snapshot desde Grafana local o cloud:
curl -s -u $GRAFANA_USER:$GRAFANA_PASS "http://localhost:3000/api/snapshots/dashboard/$DASH_UID" > evidence/grafana_security_snapshot.json

5) Módulo D — Chaos Engineering Controlado
Experimentos (ya hay scripts):
- observability/chaos/latency-injection.sh (inyecta latencia)
- observability/chaos/error-injection.sh (inyecta errores)

Recomendaciones de ejecución y evidencia:
# 1) Baseline: recopilar métricas 10 minutos antes
curl -sG 'http://localhost:9093/api/v1/query' --data-urlencode 'query=sum(rate(http_requests_total[5m])) by (job)' | jq . > evidence/chaos/baseline_requests.json

# 2) Ejecutar experimento (latency en service-b de +200ms)
bash observability/chaos/latency-injection.sh http://localhost:9092/api/products 200 > evidence/chaos/latency_run.txt

# 3) Ejecutar experimento (errores 10% en data-service)
bash observability/chaos/error-injection.sh http://localhost:8000/data/products > evidence/chaos/error_run.txt

# 4) Monitorizar alertas: guardar alertmanager API / cloud monitoring alerts en evidence
curl -s http://localhost:9093/api/v1/alerts | jq . > evidence/alerts_during_chaos.json

Comprobar MTTD < 2 minutos:
- Registra timestamp de cuando comienza el experimento y timestamp cuando la primera alerta asociada al experimento aparece. Guarda ambos en evidence/chaos/mttd.txt

Analizar SLO / error budget:
- Si definiste SLO (por ejemplo availability 99.9% = 43.2 min/month error budget), calcula consumo durante la ventana del experimento y documenta si se consumió.

6) Módulo E — Reporte de Madurez
- Completa observability/maturity/report.md con enlaces a evidence/* y captura de dashboards/traces/alertas.
- Incluye la matriz 8 dominios y justifica cada puntuación con pruebas (links a archivos en /evidence).
- Añade roadmap de 3 meses con tareas concretas y responsables.

7) Automatizar captura de evidencias (script ejemplo)
Crea scripts bash que ejecuten en orden las llamadas y guarden resultados en evidence/ con timestamp. Ejemplo minimal:

mkdir -p evidence/local
TS=$(date -u +"%Y%m%dT%H%M%SZ")
curl -sS http://localhost:8000/data/products | jq . > evidence/local/data_products_$TS.json
TRACE=$(jq -r '.trace_id' evidence/local/data_products_$TS.json)
echo $TRACE > evidence/local/trace_$TS.txt
curl -s "http://localhost:16686/api/traces/$TRACE" | jq . > evidence/local/trace_full_$TS.json

8) Checklist final antes de entregar
- evidence/* poblada con: health, traces, grafana json, prometheus queries, chaos runs, alert counts
- observability/maturity/report.md completado con links a evidence
- commits en la rama develop-taller-gcp con cambios y READMEs actualizados

---

Si quieres, hago esto por ti ahora:
- Creo este archivo en observability/LAB_VALIDATION.md (hecho).
- Puedo añadir scripts de captura automática en observability/scripts/collect_evidence.sh y commitearlos en la rama develop-taller-gcp.

Dime si quieres que cree también el script collect_evidence.sh y lo suba al repo (lo puedo hacer ahora).