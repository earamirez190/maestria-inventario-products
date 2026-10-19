# Evidencias GCP — laboratorio integrador

Fecha local: 2026-10-18 (las marcas de Cloud Logging aparecen en UTC como 2026-10-19)

Proyecto: `mydemo-505323`

Cluster: `actividad1-gke` (`us-central1-a`)
Endpoint público: `http://34.135.138.233`

## Despliegue validado

| Componente | Estado | Evidencia |
|---|---|---|
| `data-service` | `Running` (2/2 contenedores) | Cloud SQL Proxy conectado a `inventory-cloudsql`; imagen final con correlación de caos |
| `service-b` | `Running` | Readiness `/actuator/health` OK |
| aplicación principal | `Running` | LoadBalancer público |
| MySQL interno | `Running` | Persistencia de auditoría de app/service-b |
| OTel Collector | `Running` | Recepción de traces, metrics y logs |
| Cloud SQL MySQL | `RUNNABLE` | Base `inventorydb`, tabla `products` |

## Pruebas funcionales

| Solicitud | Resultado |
|---|---|
| `GET /actuator/health` | HTTP 200, DB `UP` |
| `GET /api/products` | HTTP 200 |
| `GET /api/observability/data/products` | HTTP 200, 2 productos, `cloud_provider=gcp`, `db_provider=cloud-sql` |
| `GET /api/observability/data/products?category=infra` | HTTP 200, 1 producto |

Ejemplos de `trace_id` observados en respuestas integradas: `628beef083d94f07f21911e70a74b6a3`,
`9941c13a543c9e60ae18bda6c2811a99`. El `data-service` registró también el
`trace_id` y el span de consulta SQL.

## Experimentos de caos en sandbox GKE

| Experimento | Solicitudes | Resultado observado | Restauración |
|---|---:|---|---|
| Latencia `service-b=200 ms` | 30 | 0 errores; p50 503.1 ms; p95 575.2 ms; p99 614.4 ms | `CHAOS_LATENCY_MS=0` |
| Latencia `data-service=200 ms` | 29 válidas | 29 HTTP 200; promedio 457.7 ms; p50 438.6 ms; p95 515.6 ms; p99 521.3 ms | `CHAOS_LATENCY_MS=0` |
| Error `data-service=10%` | 99 válidas | 86 HTTP 200 y 13 HTTP 500; tasa observada 13.13% | `CHAOS_ERROR_RATE=0` |
| Correlación de error | 1 solicitud | HTTP 500 controlado; Cloud Logging conservó `trace_id=0f486c5d15f49038f4b69bab1bf525ea` | `CHAOS_ERROR_RATE=0` |

Después de restaurar ambos experimentos, la ruta integrada volvió a HTTP 200.

## Observabilidad

- El Collector confirmó recepción de traces y logs mediante su exporter `debug`.
- Cloud Logging contiene registros de `Products query completada` del namespace
  `actividad1`.
- Las respuestas integradas conservaron `trace_id`; el detalle de la traza se
  consulta en Cloud Trace usando ese identificador.
- El Collector recibe métricas y las expone también por Prometheus en el puerto
  `9464`.

## Controles GCP configurados

| Capacidad | Resultado | Evidencia/identificador |
|---|---|---|
| VPC Flow Logs | Habilitados en la subred `default` de `us-central1` | Métrica `vpc_denied_traffic` |
| Métrica de errores | Creada desde Cloud Logging para `data-service` | `data_service_errors` |
| Métrica de latencia | Creada como distribución desde `request_duration` | `data_service_latency_distribution` |
| Política de error rate | Habilitada | `3165301636611085493` — `GKE data-service — error rate detectado` |
| Política correlacionada | Habilitada con error + p99 | `9817150169001650444` — `GKE data-service — errores y latencia p99` |
| Dashboard principal | Creado | `f6628f0b-d102-4fc6-a584-36044795e30a` |
| Dashboard de seguridad | Creado | `e6f87e43-65ce-44fe-bde6-1c184ad3f765` |

Los logs de una consulta normal incluyen `request_duration`, `duration`,
`trace_id` y `rows`. Los logs de caos incluyen `error_rate`, `trace_id` y
`span_id`; esto permite abrir el request fallido en Cloud Trace desde Cloud
Logging.

## Alcance pendiente

No se afirma aquí que exista un service mesh administrado ni un MTTD real
medido desde un incidente de Cloud Monitoring. El mesh administrado requiere
habilitación de GKE Enterprise/Cloud Service Mesh y permisos específicos; la
política de alertas sí quedó creada y habilitada, pero el tiempo de detección
debe capturarse desde el incidente en la consola. AWS/RDS y App Mesh quedan
fuera de esta ejecución GCP y se presentan como extensión futura.
