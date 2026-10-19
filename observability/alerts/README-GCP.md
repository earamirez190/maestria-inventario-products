# Alertas GCP del laboratorio

Estos archivos son la configuración versionada de las capacidades que se
aplicaron en el proyecto `mydemo-505323`:

- `gcp-data-service-latency.yaml`: métrica de distribución basada en
  `jsonPayload.request_duration`.
- `gcp-data-service-error-policy.json`: alerta de error rate del
  `data-service`.
- `gcp-data-service-correlation-policy.json`: correlación de error rate y p99
  superior a 200 ms, con instrucciones para buscar `trace_id` en Cloud
  Logging/Cloud Trace.

Las métricas logs-based se crearon con `gcloud logging metrics create` y las
políticas con `gcloud monitoring policies create`. Los nombres e identificadores
reales están en `evidence/gcp/RESULTADOS_20261018.md`.

El experimento de caos no debe ejecutarse en recursos compartidos. En este
laboratorio se usó únicamente el namespace `actividad1` del sandbox GKE y se
restauró `CHAOS_LATENCY_MS=0` y `CHAOS_ERROR_RATE=0` al terminar.
