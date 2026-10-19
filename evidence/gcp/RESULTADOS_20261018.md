# Evidencias GCP — laboratorio integrador

Fecha local: 2026-10-18

Proyecto: `mydemo-505323`

Cluster: `actividad1-gke` (`us-central1-a`)
Endpoint público: `http://34.135.138.233`

## Despliegue validado

| Componente | Estado | Evidencia |
|---|---|---|
| `data-service` | `Running` (2/2 contenedores) | Cloud SQL Proxy conectado a `inventory-cloudsql` |
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

Ejemplo de `trace_id` observado en la respuesta integrada: `40cf5c5f70c2bd53fd7363f13b1763c7`.
El `data-service` registró también el `trace_id` y el span de consulta SQL.

## Experimentos de caos en sandbox GKE

| Experimento | Solicitudes | Resultado observado | Restauración |
|---|---:|---|---|
| Latencia `service-b=200 ms` | 30 | 0 errores; p50 503.1 ms; p95 575.2 ms; p99 614.4 ms | `CHAOS_LATENCY_MS=0` |
| Error `data-service=10%` | 60 | 54 HTTP 200 y 6 HTTP 500; tasa observada 10% | `CHAOS_ERROR_RATE=0` |

Después de restaurar ambos experimentos, la ruta integrada volvió a HTTP 200.

## Observabilidad

- El Collector confirmó recepción de traces y logs mediante su exporter `debug`.
- Cloud Logging contiene registros de `Products query completada` del namespace
  `actividad1`.
- Las respuestas integradas conservaron `trace_id`; el detalle de la traza se
  consulta en Cloud Trace usando ese identificador.
- El Collector recibe métricas y las expone también por Prometheus en el puerto
  `9464`.

## Alcance pendiente

No se afirma aquí que exista un service mesh administrado ni una alerta de
Cloud Monitoring con MTTD medido. Esos dos elementos requieren activar la
distribución de mesh y crear/validar una política de alertas en el proyecto;
los experimentos y la instrumentación sí quedaron ejecutados y documentados.
