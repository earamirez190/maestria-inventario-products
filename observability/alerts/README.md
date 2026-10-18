# Módulo B — AIOps y correlación

La regla portable y ejecutable localmente está en
`aiops-alert-rule.yaml`. Implementa:

```text
error_rate > baseline_1h + 2 * stddev_1h
AND db_latency_p99 > 200 ms
```

La alerta incluye el servicio, el SLO, el método de detección y un enlace de
runbook. El `trace_id` se obtiene de los logs estructurados y de la respuesta
del request; no se inventa como etiqueta de una métrica. Para una alerta
enriquecida en GCP, el receptor de notificaciones debe conservar el
`trace_id` del log/span y agregar el enlace a Cloud Trace.

## Validación

```bash
curl -s http://localhost:9093/api/v1/rules | jq .
curl -s http://localhost:9093/api/v1/alerts | jq .
```

El experimento comparativo se ejecuta con:

```bash
bash observability/experiments/run-local.sh
```

Para GCP, se debe exportar la métrica a Cloud Monitoring y crear allí la
política equivalente. No se aplica automáticamente porque requiere validar el
proyecto y el canal de notificación antes de crear una alerta real.
