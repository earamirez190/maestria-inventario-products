# Entregable técnico final — Observabilidad distribuida

## 1. Datos generales

| Campo | Valor |
|---|---|
| Proyecto | `mydemo-505323` |
| Repositorio | `maestria-inventario-products` |
| Rama | `mydemo-deploy` |
| Cluster | `actividad1-gke` |
| Zona | `us-central1-a` |
| Namespace | `actividad1` |
| Endpoint público | `http://34.135.138.233` |

Este documento consolida la implementación y las evidencias observadas en el
sandbox GCP. Las capacidades que no fueron verificadas directamente se marcan
como pendientes y no como implementadas.

## 2. Arquitectura implementada

```text
Cliente
  |
  v
maestria-inventario-products  (LoadBalancer público)
  |
  +--> service-b / auditoría
  |       |
  |       +--> MySQL interno
  |
  +--> data-service
          |
          +--> Cloud SQL Proxy --> Cloud SQL MySQL

Todos los servicios --OTLP--> otel-collector
                                  |
                                  +--> Cloud Logging
                                  +--> Cloud Trace
                                  +--> Cloud Monitoring / Managed Prometheus
```

Componentes validados en el namespace `actividad1`:

- `maestria-inventario-products`.
- `service-b`.
- `data-service` con sidecar Cloud SQL Proxy.
- MySQL interno para la auditoría de la aplicación.
- `otel-collector` para recibir traces, métricas y logs.

## 3. Tres pilares de observabilidad

### Métricas

Se configuraron métricas basadas en logs y métricas de infraestructura para
observar errores, duración de solicitudes, CPU y memoria de los contenedores.
El Collector expone métricas Prometheus en el puerto `9464` y Google Managed
Service for Prometheus proporciona la recolección administrada en GKE.

### Logs

Los registros de `data-service`, `service-b` y `otel-collector` están visibles
en Cloud Logging. Los eventos de aplicación incluyen, cuando corresponde,
`trace_id`, `span_id`, duración de la solicitud, resultado y número de filas.

### Trazas

Cloud Trace confirmó trazas distribuidas con operaciones como:

```text
GET /api/observability/data/products
  -> products.data-service
     -> GET /api/data/products
        -> data-service.products
```

Una de las evidencias muestra seis intervalos relacionados y una duración
aproximada de `1.065 s`; otra muestra la misma ruta en estado exitoso con una
duración aproximada de `1.048 s`. En Cloud Logging también se observó el
`trace_id` `58f3e27fcdf402d5f41f7ef8b971a1d5`.

La evidencia confirma propagación entre servicios. En las capturas de GCP no
se observó un span independiente con `db.system`, `db.name` y `db.operation`;
por tanto, la instrumentación específica de spans SQL queda como mejora
pendiente y no se afirma como resultado comprobado.

## 4. Dashboards y alertas GCP

### Dashboard principal

**Maestría Inventario — Observabilidad y Chaos Engineering**

Incluye errores de `data-service`, latencia p99, CPU de contenedores GKE,
memoria utilizada, logs de consultas y estado del laboratorio.

[Abrir dashboard principal](https://console.cloud.google.com/monitoring/dashboards/builder/f6628f0b-d102-4fc6-a584-36044795e30a?project=mydemo-505323)

### Dashboard de seguridad

**Golden Signals de Seguridad — actividad1**

Incluye tráfico VPC rechazado, errores del `data-service`, registros de
seguridad y alcance del sandbox.

En la ventana documentada no se observaron series de tráfico VPC rechazado;
esto significa que no se detectó tráfico bloqueado durante ese intervalo, no
que el dashboard esté fallando.

[Abrir dashboard de seguridad](https://console.cloud.google.com/monitoring/dashboards/builder/e6f87e43-65ce-44fe-bde6-1c184ad3f765?project=mydemo-505323)

### Políticas de alerta

| Política | Identificador | Propósito |
|---|---|---|
| `GKE data-service — error rate detectado` | `3165301636611085493` | Detectar errores del `data-service` desde Cloud Logging |
| `GKE data-service — errores y latencia p99` | `9817150169001650444` | Correlacionar errores con latencia p99 superior al SLO |

[Abrir alertas de Monitoring](https://console.cloud.google.com/monitoring/alerting?project=mydemo-505323)

La alerta de errores fue activada durante una prueba controlada y mostró los
logs `Chaos: error inyectado`. La alerta se documentó con las etiquetas del
laboratorio y la instrucción de buscar el `trace_id` en Cloud Logging y Cloud
Trace.

## 5. Experimentos de Chaos Engineering

Los experimentos se ejecutaron únicamente sobre el sandbox GKE y se
restauraron a cero al terminar.

### Experimento 1 — Latencia en `service-b`

```bash
kubectl -n actividad1 set env deployment/service-b CHAOS_LATENCY_MS=200
kubectl -n actividad1 rollout status deployment/service-b
```

Se generaron solicitudes contra:

```text
http://34.135.138.233/api/observability/data/products
```

Resultado observado en la corrida documentada: respuestas HTTP 200, con
incremento de latencia respecto de la línea base. En la ejecución de video se
verificaron respuestas HTTP 200 con tiempos aproximados de `0.42 s` después de
activar la inyección.

Restauración:

```bash
kubectl -n actividad1 scale deployment/service-b --replicas=0
kubectl -n actividad1 set env deployment/service-b CHAOS_LATENCY_MS=0
kubectl -n actividad1 scale deployment/service-b --replicas=1
kubectl -n actividad1 rollout status deployment/service-b --timeout=180s
```

### Experimento 2 — Tasa de error del 10 % en `data-service`

```bash
kubectl -n actividad1 set env deployment/data-service CHAOS_ERROR_RATE=0.10
kubectl -n actividad1 rollout status deployment/data-service
```

En la corrida versionada se observaron 86 respuestas HTTP 200 y 13 respuestas
HTTP 500 sobre 99 solicitudes válidas, equivalente a una tasa observada de
`13.13 %`. Los logs conservaron el `trace_id` y el `span_id` de los errores.

Restauración:

```bash
kubectl -n actividad1 scale deployment/data-service --replicas=0
kubectl -n actividad1 set env deployment/data-service CHAOS_ERROR_RATE=0
kubectl -n actividad1 scale deployment/data-service --replicas=1
kubectl -n actividad1 rollout status deployment/data-service --timeout=180s
```

Después de la restauración, la ruta integrada volvió a responder HTTP 200.

> Nota: los scripts `observability/chaos/*.sh` usan Docker Compose y son para
> pruebas locales. Para el video GCP se utilizaron los cambios controlados de
> variables con `kubectl` en el namespace `actividad1`.

## 6. Resultados y análisis

| Hipótesis | Evidencia | Resultado |
|---|---|---|
| Si se agrega latencia a `service-b`, aumentará la duración de la ruta integrada | Dashboard principal, Cloud Trace y respuestas HTTP | Confirmada: la ruta continuó disponible, pero con mayor latencia |
| Si `data-service` opera con error rate del 10 %, aumentarán los errores observables | `data_service_errors`, Cloud Logging y alerta | Confirmada: se observaron respuestas 500, logs de caos y alerta activa |
| Al retirar la inyección, el sistema recuperará su comportamiento normal | Nueva ejecución HTTP 200 y métricas posteriores | Confirmada en el sandbox |

La debilidad principal identificada es la sensibilidad de la latencia y de la
tasa de errores en la cadena distribuida. La remediación propuesta es mantener
timeouts, retries con backoff, circuit breakers, límites de recursos,
dashboards con SLO y alertas correlacionadas.

El MTTD exacto debe calcularse con el timestamp de inicio del experimento y el
timestamp de apertura del incidente en Cloud Monitoring. En esta entrega no se
inventa un valor de MTTD cuando no existe una medición temporal completa.

## 7. Estado de Prometheus y Grafana

En GKE no se encontraron pods `prometheus` ni `grafana` dentro del namespace
`actividad1`. El entorno remoto utiliza:

- Google Managed Service for Prometheus, con collectors en `gmp-system`.
- `otel-collector` en `actividad1`, con puerto de métricas `9464`.
- Cloud Monitoring como interfaz remota para dashboards, métricas y alertas.

Grafana, Loki, Jaeger y Prometheus standalone están definidos para el entorno
local de Docker Compose. No deben presentarse como servicios desplegados dentro
del GKE de este proyecto salvo que se desplieguen y se evidencien por separado.

## 8. Madurez y pendientes

| Dominio | Estado |
|---|---|
| Instrumentación HTTP | Implementada y evidenciada |
| Logs correlacionados | Implementada y evidenciada |
| Trazas distribuidas | Implementada y evidenciada |
| Métricas y dashboards GCP | Implementada y evidenciada |
| Alertas de errores y correlación | Implementada y evidenciada |
| VPC Flow Logs | Configurados; sin tráfico rechazado observado en la ventana |
| Spans SQL semánticos | Pendiente de evidencia independiente en Cloud Trace |
| Service Mesh administrado | Pendiente de habilitación y permisos |
| Security Command Center avanzado | Depende de la edición y permisos de la organización |
| AWS RDS/App Mesh | Fuera del alcance de esta ejecución GCP |

## 9. Evidencia versionada

- `evidence/gcp/RESULTADOS_20261018.md`: validación GCP y resultados de pruebas.
- `evidence/chaos/RESULTADOS_20261018T234346Z.md`: resumen de experimentos.
- `evidence/chaos/run_20261018T234346Z/`: CSV, métricas, alertas y resumen JSON.
- `observability/dashboards/cloud-monitoring-dashboard.json`: dashboard principal.
- `observability/dashboards/golden-signals-security-gcp.json`: dashboard de seguridad.
- `observability/alerts/`: políticas y documentación de alertas.
- `observability/chaos/`: scripts locales y manifiestos de experimentos.
- `observability/maturity/report.md`: evaluación de madurez y roadmap.

## 10. Conclusión

La solución quedó desplegada en el sandbox GCP con `data-service`,
OpenTelemetry Collector, Cloud Logging, Cloud Trace, Cloud Monitoring,
Managed Prometheus, dashboards y alertas. Los dos experimentos de caos fueron
ejecutados de forma controlada, sus efectos fueron observados y los valores de
caos fueron restaurados. Las capacidades pendientes están identificadas de
forma explícita para que el informe diferencie entre evidencia obtenida y
trabajo futuro.
