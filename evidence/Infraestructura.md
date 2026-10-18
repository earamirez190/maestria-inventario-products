Entregable Técnico Final
Observabilidad Distribuida sobre Google Kubernetes Engine (GKE)
Proyecto
Repositorio: maestria-inventario-products
Rama: develop-taller-gcp
Cloud Provider: Google Cloud Platform (GCP)
Cluster: GKE
Namespace Principal: actividad1

Resumen Ejecutivo
La solución implementa una arquitectura observable desplegada sobre Google Kubernetes Engine (GKE) utilizando OpenTelemetry, Prometheus, Grafana, Loki y Litmus Chaos Engineering.

Se implementaron los tres pilares de observabilidad:

Métricas
Logs
Trazas
La plataforma permite monitorear los microservicios, la base de datos, los recursos JVM, la infraestructura Kubernetes y el comportamiento del sistema durante experimentos de Chaos Engineering.

1. Infrastructure as Code (IaC)
1.1 Arquitectura Kubernetes
La solución fue desplegada sobre Google Kubernetes Engine utilizando manifiestos Kubernetes para la orquestación de los componentes.

Componentes desplegados
maestria-inventario-products
mysql
grafana
loki
otel-collector
litmus
Evidencia
kubectl get pods -A
Resultado:

actividad1    maestria-inventario-products
actividad1    mysql
actividad1    grafana
actividad1    loki
actividad1    otel-collector
litmus        chaos-operator-ce
1.2 Namespaces utilizados
actividad1
litmus
gmp-system
gmp-public
kube-system
Propósito de cada namespace
Namespace	Función
actividad1	Aplicaciones de negocio
litmus	Chaos Engineering
gmp-system	Google Managed Prometheus
kube-system	Componentes internos GKE
1.3 Google Kubernetes Engine
Capacidades utilizadas
Despliegue de contenedores
Descubrimiento de servicios
Escalabilidad
Monitoreo integrado
Integración con Cloud Monitoring
1.4 Google Managed Prometheus
Componentes detectados:

collector-br9nw
collector-qxlvf
gmp-operator
Funciones:

Recolección de métricas
Almacenamiento temporal
Integración con Cloud Monitoring
1.5 Artifact Registry
Utilizado para:

Almacenamiento de imágenes Docker
Versionamiento
Integración con Cloud Build
1.6 Cloud Build
Responsabilidades:

Compilación
Empaquetado
Construcción Docker
Despliegue
2. Código de Instrumentación
2.1 OpenTelemetry
La solución utiliza OpenTelemetry para implementar observabilidad distribuida.

Componentes observados
HTTP
JVM
Base de Datos
Collector
Kubernetes
2.2 Instrumentación HTTP
Métricas detectadas:

http_server_requests_seconds_bucket
http_server_requests_seconds_count
http_server_requests_seconds_sum
http_server_request_duration_seconds_bucket
http_server_request_duration_seconds_count
http_server_request_duration_seconds_sum
Capacidades:

Latencia
Throughput
Golden Signals
SLOs
2.3 Instrumentación JVM
Métricas recolectadas:

jvm_memory_used_bytes
jvm_memory_committed_bytes
jvm_memory_max_bytes
jvm_gc_pause_seconds_count
jvm_gc_duration_seconds_count
jvm_thread_count
Capacidades:

Consumo de memoria
Garbage Collection
Gestión de hilos
Salud JVM
2.4 Instrumentación de Base de Datos
JDBC
jdbc_connections_active
jdbc_connections_idle
jdbc_connections_max
jdbc_connections_min
HikariCP
hikaricp_connections_active
hikaricp_connections_idle
hikaricp_connections_pending
hikaricp_connections_max
Capacidades:

Pool de conexiones
Saturación
Disponibilidad de conexiones
2.5 Instrumentación OpenTelemetry Collector
Métricas identificadas:

otelcol_processor_incoming_items
otelcol_processor_outgoing_items
otelcol_exporter_sent_spans
otelcol_exporter_queue_size
otelcol_exporter_in_flight_requests
3. Configuración de Observabilidad
3.1 OpenTelemetry Collector
Funciones implementadas:

Receivers
OTLP
Processors
batch
memory_limiter
Exporters
Prometheus
Grafana
Cloud Monitoring
3.2 Prometheus
Utilizado para:

Recolección de métricas
PromQL
Métricas de aplicaciones
Métricas monitoreadas
HTTP
JVM
JDBC
HikariCP
OpenTelemetry
3.3 Grafana
Dashboard implementado:

Golden Signals
Throughput
Latencia
Errores
Disponibilidad
Recursos
CPU
Memoria
Garbage Collection
Base de Datos
JDBC
HikariCP
OpenTelemetry
Spans exportados
Procesamiento de datos
3.4 Loki
Utilizado para:

Centralización de logs
Correlación de eventos
Análisis operacional
4. Scripts y Automatización
Despliegue
kubectl apply -f .
Validación de Pods
kubectl get pods -A
Validación de Servicios
kubectl get svc -A
Logs
kubectl logs deployment/otel-collector -n actividad1
Consultas Prometheus
Throughput
sum(rate(http_server_requests_seconds_count[5m]))
Latencia Promedio
rate(http_server_requests_seconds_sum[5m])
/
rate(http_server_requests_seconds_count[5m])
Latencia P95
histogram_quantile(
  0.95,
  sum(rate(http_server_requests_seconds_bucket[5m])) by (le)
)
Latencia P99
histogram_quantile(
  0.99,
  sum(rate(http_server_requests_seconds_bucket[5m])) by (le)
)
CPU
system_cpu_usage
Memoria JVM
jvm_memory_used_bytes
JDBC
jdbc_connections_active
OpenTelemetry
rate(otelcol_exporter_sent_spans[5m])
5. Dashboard Cloud Monitoring
Se implementó un dashboard en Cloud Monitoring para observar:

Aplicación
Throughput
Latencia
Recursos
Infraestructura
CPU Nodes
Memoria Nodes
Disco
Red
Kubernetes
Pods
Reinicios
Consumo CPU
Consumo Memoria
OpenTelemetry
Tráfico procesado
Exportación de spans
6. Chaos Engineering
Plataforma
Litmus Chaos
Namespace:

litmus
Componentes Detectados
chaos-operator-ce
pod-network-latency
maestria-pod-network-latency-engine-runner
Experimento Ejecutado
Pod Network Latency
Objetivo:

Incrementar artificialmente la latencia de red
Variables monitoreadas:

Throughput
Latencia P95
Latencia P99
CPU
Memoria
Spans
7. Métricas Observadas
HTTP
http_server_requests_seconds_bucket
http_server_requests_seconds_count
http_server_request_duration_seconds_bucket
JVM
jvm_memory_used_bytes
jvm_memory_committed_bytes
jvm_gc_pause_seconds_count
jvm_thread_count
JDBC
jdbc_connections_active
jdbc_connections_idle
HikariCP
hikaricp_connections_active
hikaricp_connections_idle
hikaricp_connections_pending
OpenTelemetry
otelcol_processor_incoming_items
otelcol_processor_outgoing_items
otelcol_exporter_sent_spans
8. Logs
Flujo implementado:

Aplicación
    ↓
OpenTelemetry
    ↓
Loki
    ↓
Grafana
Capacidades:

Búsqueda de errores
Correlación temporal
Análisis de eventos
9. Trazas Distribuidas
Flujo:

Cliente
    ↓
maestria-inventario-products
    ↓
MySQL
Capacidades:

Seguimiento distribuido
Diagnóstico de latencia
Identificación de cuellos de botella
10. Conclusiones
La solución implementa exitosamente una plataforma moderna de observabilidad basada en estándares OpenTelemetry desplegada sobre Google Kubernetes Engine.

Logros obtenidos
✅ Instrumentación de métricas

✅ Instrumentación de logs

✅ Instrumentación de trazas

✅ Integración OpenTelemetry

✅ Integración Prometheus

✅ Integración Grafana

✅ Integración Loki

✅ Integración Cloud Monitoring

✅ Integración Google Managed Prometheus

✅ Monitoreo de JVM

✅ Monitoreo JDBC

✅ Monitoreo HikariCP

✅ Monitoreo Kubernetes

✅ Dashboard Cloud Monitoring

✅ Dashboard Grafana

✅ Chaos Engineering con Litmus

✅ Correlación entre métricas, logs y trazas

✅ Observabilidad end-to-end de la plataforma



