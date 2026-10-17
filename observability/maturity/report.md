# Reporte de madurez inicial — Observability

Esta es una autoevaluación inicial (plantilla). Completar con evidencias después de ejecutar los módulos.

| Dominio | Puntuación (1-5) | Evidencia / Comentarios |
|---|---:|---|
| Instrumentation | 2 | Se instrumentaron servicios con OTel SDK (básico). Falta cobertura completa y logs semánticos. |
| Tracing | 2 | Traces end-to-end en entorno de pruebas. Falta sampleo y enriquecimiento. |
| Metrics | 2 | Métricas básicas expuestas; falta SLIs y storage a largo plazo. |
| Logs | 1 | Logs no centralizados todavía. |
| Storage | 1 | Retención y backend no definidos. |
| Analysis | 1 | Alertas básicas, falta AIOps configurado. |
| Alerting | 1 | Plantillas iniciales. |
| Operations | 1 | Runbooks y playbooks incompletos. |

## Roadmap 3 meses
- Semana 1-2: Completar instrumentación en todos los servicios y configurar collector en cluster.
- Semana 3-4: Implementar dashboards y alertas básicas; definir SLOs y SLIs.
- Mes 2: Habilitar AIOps/Anomaly Detection y pruebas controladas.
- Mes 3: Chaos engineering y ajuste de runbooks; madurez y reporte final.
