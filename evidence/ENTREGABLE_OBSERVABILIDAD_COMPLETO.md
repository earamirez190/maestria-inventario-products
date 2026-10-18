# ENTREGABLE TÉCNICO FINAL
## Observabilidad Distribuida sobre Google Kubernetes Engine (GKE)

**Proyecto:** maestria-inventario-products  
**Rama:** develop-taller-gcp  
**Cloud Provider:** Google Cloud Platform (GCP)  
**Cluster:** GKE  
**Namespace principal:** actividad1

---

# 1. Introducción

Este documento consolida la evidencia técnica de la implementación de observabilidad distribuida para la plataforma maestria-inventario-products desplegada sobre Google Kubernetes Engine (GKE).

La solución incorpora los tres pilares fundamentales de observabilidad:

- Métricas

![alt text](image-23.png)

![alt text](image-24.png)

- Logs

![alt text](image-22.png)

- Trazas

![alt text](image-21.png)

Adicionalmente se implementó monitoreo de infraestructura Kubernetes, OpenTelemetry, Prometheus, Grafana, Loki y Chaos Engineering mediante Litmus.

![alt text](image-25.png)

---

# 2. Arquitectura de la Solución

## Componentes Desplegados

### Aplicación
- maestria-inventario-products

### Base de Datos
- MySQL

![alt text](image-20.png)

### Observabilidad
- OpenTelemetry Collector

![alt text](image-28.png)

- Prometheus (Google Managed Prometheus)

![alt text](image-27.png)

- Grafana

![alt text](image-26.png)

- Loki

![alt text](image-29.png)

### Chaos Engineering
- Litmus Chaos
- Chaos Operator

---

# 3. Infrastructure as Code (IaC)

## Despliegue en Kubernetes

La plataforma fue desplegada sobre Google Kubernetes Engine mediante manifiestos Kubernetes.

### Componentes Observados

```text
grafana
loki
mysql

![alt text](image-30.png)

maestria-inventario-products
otel-collector
chaos-operator-ce
```

## Google Kubernetes Engine

Características utilizadas:

- Contenedores administrados
- Escalamiento automático
- Service Discovery
- Monitoreo nativo
- Integración con Cloud Monitoring
- Integración con Managed Prometheus

## Artifact Registry

Utilizado para almacenamiento y distribución de imágenes Docker.

## Cloud Build

Utilizado para compilar, construir imágenes y desplegar la solución.

---

# 4. Instrumentación OpenTelemetry

## Instrumentación HTTP

Métricas observadas:

```text
http_server_requests_seconds_bucket
http_server_requests_seconds_count
http_server_requests_seconds_sum
http_server_request_duration_seconds_bucket
http_server_request_duration_seconds_count
http_server_request_duration_seconds_sum
```

## Instrumentación JVM

```text
jvm_memory_used_bytes
jvm_memory_committed_bytes
jvm_memory_max_bytes
jvm_gc_duration_seconds_count
jvm_gc_pause_seconds_count
jvm_thread_count
```

## Instrumentación Base de Datos

### JDBC

```text
jdbc_connections_active
jdbc_connections_idle
jdbc_connections_max
jdbc_connections_min
```

### HikariCP

```text
hikaricp_connections_active
hikaricp_connections_idle
hikaricp_connections_pending
hikaricp_connections_max
```

## Instrumentación OpenTelemetry Collector

```text
otelcol_processor_incoming_items
otelcol_processor_outgoing_items
otelcol_exporter_sent_spans
otelcol_exporter_queue_size
```

---

# 5. Dashboard de Observabilidad

## Consultas PromQL Principales

### Throughput

```promql
sum(rate(http_server_requests_seconds_count[5m]))
```

### Latencia P95

```promql
histogram_quantile(0.95,sum(rate(http_server_requests_seconds_bucket[5m])) by (le))
```

### Latencia P99

```promql
histogram_quantile(0.99,sum(rate(http_server_requests_seconds_bucket[5m])) by (le))
```

### CPU

```promql
system_cpu_usage
```

### Memoria JVM

```promql
jvm_memory_used_bytes
```

---

# 6. Logs

Flujo implementado:

```text
Aplicación
  ↓
OpenTelemetry
  ↓
Loki
  ↓
Grafana
```

---

# 7. Trazas Distribuidas

Flujo observado:

```text
Cliente
  ↓
maestria-inventario-products
  ↓
MySQL
```

---

# 8. Chaos Engineering

Namespace:

```text
litmus
```

Experimento observado:

cat <<EOF > pod-delete.yaml
apiVersion: litmuschaos.io/v1alpha1
kind: ChaosEngine
metadata:
  name: pod-delete
  namespace: actividad1
spec:
  appinfo:
    appns: actividad1
    applabel: app=data-service
    appkind: deployment
  engineState: active
  experiments:
    - name: pod-delete
EOF

```text
pod-network-latency
```

Métricas monitoreadas:

- Throughput
- Latencia P95
- Latencia P99
- CPU
- Memoria
- Spans exportados


