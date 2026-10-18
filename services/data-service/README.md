# data-service

Microservicio FastAPI para consultar el catálogo en PostgreSQL local, GCP Cloud SQL o AWS RDS según las variables de entorno. Incluye OpenTelemetry para trazas, métricas y logs estructurados con `trace_id`.

Endpoints:

- `GET /health`
- `GET /data/products?category=all`
- `GET /data/analytics/{product_id}`
- `GET /chaos/status`

## Variables principales

- `DATABASE_URL`: DSN de PostgreSQL. En GCP se puede usar Cloud SQL Auth Proxy o conexión privada.
- `CLOUD_PROVIDER`: `gcp`, `aws` o `local`.
- `DATABASE_PROVIDER`: `cloud-sql`, `rds` o `postgres-local`.
- `OTEL_EXPORTER_OTLP_ENDPOINT`: endpoint OTLP del collector.
- `CHAOS_LATENCY_MS` y `CHAOS_ERROR_RATE`: controles del experimento de caos.

El archivo `db/init.sql` crea datos de demostración para el entorno local. No contiene credenciales cloud.
