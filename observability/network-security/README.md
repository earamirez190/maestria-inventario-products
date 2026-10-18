# Módulo C — Network & Security Observability

Este directorio contiene la guía reproducible y los puntos de integración. Los
comandos de GCP son intencionalmente de ejecución manual: no se aplican desde
Docker Compose ni desde CI sin una revisión del equipo.

## GCP

Habilitar VPC Flow Logs en la subred que aloja GKE:

```bash
gcloud compute networks subnets update SUBNET_NAME \
  --region=REGION \
  --enable-flow-logs
```

En Cloud Logging, filtrar `resource.type="gce_subnetwork"` y crear métricas
basadas en logs para tráfico rechazado y volumen N-S/E-W. Security Command
Center debe aportar los hallazgos activos, severidad y CVEs del proyecto.

## Evidencia mínima

- Captura del estado de Flow Logs y del filtro de Cloud Logging.
- Captura del dashboard `golden-signals-security.json`.
- Conteo de hallazgos y una interpretación de los riesgos.
- Enlace a la alerta y al runbook utilizado.

## Limitación actual

La parte local valida Collector, métricas, logs y trazas. La evidencia de Flow
Logs, SCC, Cloud SQL y GKE solo puede completarse cuando el equipo entregue el
proyecto y la cuenta tenga permisos suficientes.
