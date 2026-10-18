# Reporte de madurez — Observability

Esta matriz separa la capacidad implementada en el repositorio de la evidencia
que todavía debe capturarse en GCP/AWS. Las puntuaciones no sustituyen las
capturas: después de ejecutar el checklist se deben enlazar los archivos de
`evidence/` generados en la corrida.

| Dominio | Puntuación (1-5) | Evidencia / Comentarios |
|---|---:|---|
| Instrumentation | 4 | App, service-b y data-service tienen instrumentación OTel; data-service incluye spans DB, métricas y logs OTLP. Evidencia: `services/data-service/src/main.py` y `observability/otel-collector-config.yaml`. |
| Tracing | 3 | Ruta app → service-b → data-service devuelve `trace_id` y exporta OTLP local. Falta evidencia de Cloud Trace/X-Ray en nube. |
| Metrics | 4 | Métricas de requests, errores, p99 DB y conexiones; reglas de recording y dashboards incluidos. Falta retención gestionada. |
| Logs | 3 | Logs JSON con `trace_id`/`span_id` y pipeline Loki local. Falta validar consultas centralizadas en GCP/AWS. |
| Storage | 2 | Persistencia local y Cloud SQL/RDS parametrizados; falta confirmar backup, retención y recuperación en cada cloud. |
| Analysis | 3 | Baseline + 2σ y comparación contra umbral estático implementados en Prometheus. Falta ejecutar la comparación con ventanas reales. |
| Alerting | 3 | Alertas de correlación, p99 y error rate con runbook; falta canal de notificación y enriquecimiento cloud. |
| Operations | 3 | Manifiestos, IaC GCP, scripts de chaos y recolección de evidencia versionados. Falta ejecutar rollback y documentar MTTD real. |

## Evidencia requerida para cerrar la evaluación

1. `evidence/local/` con health, readiness, respuesta con `trace_id`, métricas,
   logs y reglas.
2. `evidence/chaos/run_<timestamp>/summary.json` con baseline, latencia,
   errores, p95, tasa de error y tiempos de alerta.
3. Captura/export del dashboard de Monitoring y de los logs de Flow Logs.
4. Captura de la alerta con enlace al trace y registro de MTTD.
5. Confirmación de los recursos Cloud SQL/GKE/RDS y sus controles de acceso.

## Roadmap de 3 meses

- Semanas 1–2: cerrar GKE/Cloud SQL, collector gestionado y SLOs formales.
- Semanas 3–4: habilitar Flow Logs, Security Command Center y canales de alerta.
- Mes 2: comparar AIOps contra umbrales estáticos con al menos tres ventanas de
  carga y ajustar el error budget.
- Mes 3: repetir chaos en sandbox, validar rollback, revisar permisos y publicar
  el reporte PDF de 10 páginas con video y evidencias reproducibles.
