# Checklist de ejecución y evidencias — Módulos A–E

Usar la rama `mydemo-deploy` para el proyecto propio. La rama
`feature/lab-integrador-gcp` conserva las referencias del proyecto compartido.
Los experimentos solo se ejecutan en Docker local o en un sandbox controlado.

## 0. Validación del repositorio

```bash
git checkout mydemo-deploy
git pull --ff-only
git status
docker compose config >/dev/null
```

## A. Arquitectura y tres pilares

```bash
docker compose up -d --build
curl -sS http://localhost:8002/health | jq .
curl -sS http://localhost:8002/ready | jq .
curl -sS http://localhost:9092/api/observability/data/products | jq .
curl -sS http://localhost:9464/metrics | grep -E 'data_requests_total|db_query_duration_seconds'
```

Guardar la respuesta del último request: contiene `trace_id`. Revisar en
Jaeger/Grafana el recorrido `app → service-b → data-service → DB` y los
atributos `db.system`, `db.name`, `db.operation` y `db.statement`.

En GKE, el secreto `database-secret` debe tener `username`, `password` y
`root-password`. `data-service` usa Cloud SQL mediante el proxy; `app` y
`service-b` usan el MySQL interno para la persistencia de auditoría.

## B. AIOps

```bash
curl -s http://localhost:9093/api/v1/rules | jq . > evidence/local/prometheus-rules.json
curl -s http://localhost:9093/api/v1/alerts | jq . > evidence/local/prometheus-alerts.json
```

La regla correlaciona `baseline + 2σ` con p99 de DB superior a 200 ms. Para la
entrega se debe conservar una corrida sin anomalía y otra con anomalía, y
comparar el número de alertas en la misma ventana.

## C. Red y seguridad

```bash
PROJECT_ID=mydemo-505323 bash observability/network-security/gcp-setup.sh
```

Ese comando solo muestra lo que se aplicaría. Para aplicarlo en un sandbox,
usar `APPLY=1` y después capturar Flow Logs, hallazgos de SCC y el dashboard de
`observability/dashboards/golden-signals-security.json`.

## D. Chaos controlado

```bash
bash observability/experiments/run-local.sh
```

El script guarda baseline, los dos experimentos, alertas, métricas y un
`summary.json`. Completar allí el MTTD comparando el timestamp de inicio con el
timestamp de la primera alerta. El objetivo es menor o igual a 120 segundos.

## E. Madurez y entrega

Actualizar `observability/maturity/report.md` con los enlaces a la carpeta de
evidencia. El repositorio debe terminar con un tag final:

```bash
git tag -a v1.0 -m "Laboratorio integrador de observabilidad"
git push origin v1.0
```

El PDF de 10 páginas y el video deben mostrar únicamente resultados realmente
observados; las capacidades pendientes de AWS/RDS o GCP deben marcarse como
pendientes y no como implementadas.
