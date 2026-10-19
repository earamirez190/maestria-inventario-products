# Reporte de madurez — Observability

Esta matriz separa la capacidad implementada en el repositorio de la evidencia
que todavía debe capturarse en GCP/AWS. Las puntuaciones no sustituyen las
capturas: después de ejecutar el checklist se deben enlazar los archivos de
`evidence/` generados en la corrida.

| Dominio | Puntuación (1-5) | Evidencia / Comentarios |
|---|---:|---|
| Instrumentation | 4 | App, service-b y data-service tienen instrumentación OTel; data-service incluye spans DB, métricas y logs OTLP. Los logs de caos incluyen `trace_id` y `span_id`. Evidencia: `services/data-service/src/main.py`. |
| Tracing | 4 | La ruta app → service-b → data-service devuelve `trace_id`; el Collector exporta a Cloud Trace y Cloud Logging conserva la correlación. Evidencia: `evidence/gcp/RESULTADOS_20261018.md`. |
| Metrics | 4 | Métricas de requests, errores, latencia completa y consultas DB; existen dashboards y métricas logs-based en GCP. Falta retención/SLO gestionado formal. |
| Logs | 4 | Logs JSON con `trace_id`/`span_id`, exportación OTLP y consulta confirmada en Cloud Logging. AWS queda pendiente. |
| Storage | 3 | Cloud SQL MySQL operativo con tabla `products` y proxy autenticado mediante Workload Identity; backup/recuperación y RDS no fueron validados. |
| Analysis | 4 | Existen baseline + 2σ local y métricas GCP para errores/latencia; la comparación contra umbral estático está definida en la política correlacionada. |
| Alerting | 4 | Políticas GCP de error rate y correlación error + p99 creadas, habilitadas y documentadas con `trace_id`; falta medir MTTD a partir de un incidente visible. |
| Operations | 4 | IaC, GKE, Cloud SQL, Workload Identity, dashboards, Flow Logs, chaos con restauración y evidencia versionados. Service mesh administrado y MTTD son pendientes explícitos. |

## Evidencia requerida para cerrar la evaluación

1. `evidence/local/` con health, readiness, respuesta con `trace_id`, métricas,
   logs y reglas.
2. `evidence/chaos/run_<timestamp>/summary.json` con baseline, latencia,
   errores, p95, tasa de error y tiempos de alerta.
3. Captura/export del dashboard de Monitoring y de los logs de Flow Logs. En
   GCP ya están creados `f6628f0b-d102-4fc6-a584-36044795e30a` y
   `e6f87e43-65ce-44fe-bde6-1c184ad3f765`.
4. Captura del incidente de la política `3165301636611085493` con enlace al
   trace y registro de MTTD; esta es la única evidencia GCP aún manual.
5. Confirmación de los recursos Cloud SQL/GKE/RDS y sus controles de acceso.

## Roadmap de 3 meses

- Semanas 1–2: capturar el incidente de Cloud Monitoring y el MTTD real; cerrar
  los SLOs formales y canales de notificación.
- Semanas 3–4: habilitar/validar Security Command Center y Flow Logs con la
  edición disponible en la organización.
- Mes 2: comparar AIOps contra umbrales estáticos con al menos tres ventanas de
  carga y ajustar el error budget.
- Mes 3: habilitar service mesh administrado en un sandbox con capacidad
  suficiente, repetir chaos y publicar el PDF de 10 páginas con video y
  evidencias reproducibles.
