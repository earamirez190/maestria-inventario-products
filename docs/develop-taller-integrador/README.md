# Taller Integrador — Observabilidad (Módulos A–E)

Este documento describe los requerimientos, entregables y criterios de validación para la rama `develop-taller-integrador`.

## Resumen
Incluir en la rama `develop-taller-integrador` una solución de observabilidad end-to-end para la aplicación distribuida, con: un nuevo microservicio `data-service` conectado a bases de datos en GCP Cloud SQL y AWS RDS, instrumentación completa con OpenTelemetry, reglas AIOps para detección automática de anomalías, visibilidad de red y seguridad, experimentos de Chaos Engineering y un reporte de madurez.

---

## Módulo A — Arquitectura Observable Completa
Objetivo: Extender la arquitectura con `data-service` y asegurar trazabilidad, métricas y logs completas.

Tareas:
- Añadir nuevo microservicio `data-service` (esqueleto) que acceda a GCP Cloud SQL y AWS RDS.
- Instrumentar todos los servicios (service-a, service-b, data-service) con OpenTelemetry SDK (traces, metrics, logs).
- Añadir spans de base de datos usando OTel DB Semantic Conventions (db.system, db.name, db.statement, db.connection_string, db.operation, etc.).
- Configuración de exportadores: OTLP (gRPC/HTTP) hacia collector/observability backend (por ejemplo, Cloud Trace/Cloud Monitoring / AWS X-Ray/Prometheus+Grafana/Tempo/Loki según entorno).
- Implementar service mesh básico (Cloud Service Mesh / AWS App Mesh o Istio/Linkerd si procede) para observabilidad L7 (mTLS opcional, métricas y traces a nivel malla).

Entregables:
- Código esqueleto de `data-service` en `services/data-service/`.
- Configuración de OTel en `observability/otel-config.yaml` y ejemplo de SDK bootstrap en cada servicio.
- Diagramas de arquitectura y README con pasos para desplegar local/cluster.

Criterios de aceptación:
- Traces end-to-end que muestran requests desde ingress → service-a → service-b → data-service con spans de DB.
- Métricas básicas (latency p50/p90/p99, request_rate, error_rate) disponibles en backend elegido.

---

## Módulo B — AIOps: Detección Automática de Anomalías
Objetivo: Detectar anomalías automáticamente y reducir alertas ruidosas.

Tareas:
- Configurar Anomaly Detection: usar GCP Cloud Monitoring Anomaly Detection o AWS DevOps Guru (según entorno de despliegue del data-service).
- Implementar regla de correlación: cuando
  - error_rate > baseline + 2σ
  - Y latency_p99 > SLO_threshold
  - → generar alerta enriquecida que incluya trace_id del request fallido.
- Crear playbook de correlación: cómo adjuntar trace_id a la alerta (enriquecimiento via trace linking en la alerta o incluir link al trace en el payload).
- Ejecutar pruebas para comparar tasa de alertas con y sin detección (medición de reducción de ruido).

Entregables:
- Plantilla de alerta / regla en IaC (Policy/Alerting) dentro de `observability/alerts/`.
- Script o notebook con experimento que demuestre reducción de alertas ruidosas.

Criterios de aceptación:
- Alertas correlacionadas incluyen trace_id y link al trace.
- Documentado ejemplo donde sistema con AIOps produce menos alertas que umbrales estáticos.

---

## Módulo C — Network and Security Observability
Objetivo: Visibilidad de tráfico e indicadores de seguridad.

Tareas:
- Habilitar VPC Flow Logs (GCP) y VPC Flow Logs (AWS) para los entornos donde corran los servicios.
- Configurar alertas sobre tráfico anómalo entre servicios (picos, patrones E/W inusuales, datos exfiltration sospechosa simple).
- Habilitar Security Command Center (GCP) o AWS Security Hub básico y enlazar hallazgos a dashboard.
- Crear dashboard "Golden Signals de Seguridad" con: intentos de autenticación fallidos, tráfico N-S/E-W por servicio, CVEs activos (si aplica).

Entregables:
- Instrucciones y ejemplos de configuración de VPC Flow Logs (terraform/console) en `observability/network-security/`.
- Dashboard Grafana/Looker/Cloud Console JSON en `observability/dashboards/`.

Criterios de aceptación:
- Flujo de logs disponible y visualizable en dashboard.
- Alertas de tráfico anómalo que disparan en pruebas controladas.

---

## Módulo D — Chaos Engineering Controlado
Objetivo: Verificar que el sistema de observabilidad detecta degradaciones y que SLOs/error budget son medidos.

Experimentos (2):
1) Inyección de latencia en `service-b` (+200 ms)
2) Inyección de errores (error rate 10%) en `data-service`

Tareas:
- Planificar experimentos con herramientas como Litmus, Chaos Mesh, Gremlin o scripts simples (tc/netem, fault injection HTTP).
- Ejecutar experimentos y medir: tiempo hasta detección (MTTD objetivo < 2 minutos), cambio en SLO, consumo de error budget.
- Documentar: ¿Se degradó el SLO? ¿Se consumió error budget? ¿La alerta fue accionable? (runbook)

Entregables:
- Scripts y manifiestos de experimentos en `observability/chaos/`.
- Informe de resultados con métricas temporales y evidencias (traces, alerts).

Criterios de aceptación:
- Observability detecta anomalías y genera alertas en < 2 minutos en ambos experimentos.
- Informe con evidencia y recomendaciones.

---

## Módulo E — Reporte de Madurez de Observabilidad
Objetivo: Autoevaluación contra Observability Foundation Blueprint (8 dominios) con escala 1–5 y roadmap a 3 meses.

Tareas:
- Realizar autoevaluación de la solución implementada en 8 dominios (por ejemplo: instrumentation, tracing, metrics, logs, storage, analysis, alerting, operations).
- Puntuar cada dominio 1–5 con evidencias.
- Proponer roadmap de mejoras para alcanzar el siguiente nivel en 3 meses (tareas, responsables, estimación de esfuerzo).

Entregables:
- `observability/maturity/report.md` con la matriz de madurez, evidencias y roadmap.

Criterios de aceptación:
- Matriz completada con evidencias (links a dashboards, alertas, trazas, experimentos).
- Roadmap claro y priorizado para 3 meses.

---

## Estructura de carpetas sugerida (rama `develop-taller-integrador`)
- services/data-service/
  - src/ (esqueleto)
  - Dockerfile
- observability/
  - otel-config.yaml
  - collector/ (opentelemetry-collector config)
  - alerts/ (plantillas de alertas / IaC)
  - dashboards/ (JSON / Grafana / Cloud dashboards)
  - network-security/ (VPC Flow Logs instrucciones / terraform snippets)
  - chaos/ (scripts / manifests)
  - maturity/report.md

## Siguientes pasos que puedo ejecutar ahora
- Crear el esqueleto inicial en `services/data-service/` (código mínimo, Dockerfile, README).
- Añadir `observability/otel-config.yaml` y ejemplo de bootstrap para SDK en cada servicio.
- Crear plantillas de alertas y dashboard inicial.

Si quieres, procedo ahora a crear el esqueleto del `data-service` y los archivos base de `observability/` en la rama `develop-taller-integrador`.
