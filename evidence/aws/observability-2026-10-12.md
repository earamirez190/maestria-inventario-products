# Evidencia de observabilidad AWS — 2026-10-12

## Estado del despliegue

- ECS cluster: `maestria-observabilidad-cluster`
- ECS service: `maestria-observabilidad-service`
- Estado: `ACTIVE`, 1 tarea deseada y 1 tarea ejecutándose.
- ALB: `maestria-observabilidad-alb`
- RDS: MySQL privado usado por los dos microservicios.

## Tres pilares

### Logs

Los logs de aplicación llegan a CloudWatch Logs en `/ecs/maestria-observabilidad` como JSON estructurado. La búsqueda por `trace_id` durante la ventana del benchmark encontró 12.201 eventos de `Products listed: count=5`, demostrando que cada solicitud mantiene su contexto de trazabilidad en el log.

Ejemplo de campos observados:

```json
{
  "service.name": "maestria-inventario-products",
  "message": "Products listed: count=5",
  "trace_id": "d3aaad6f994275576b56193ae7309b39",
  "span_id": "2c68f028296c63d5"
}
```

### Trazas

X-Ray registró 12.223 trazas en la ventana del benchmark. Para las cinco altas de productos de demostración se comprobaron cinco trazas distribuidas que contienen simultáneamente:

- `maestria-inventario-products`;
- `maestria-inventario-audit`;
- `maestria_inventario_products@maestria-inventario-mysql...`.

Esto demuestra la propagación del contexto entre el servicio principal, el servicio de auditoría y MySQL.

### Métricas

El Collector recibe OTLP y exporta trazas a X-Ray. ECS y el ALB proporcionan métricas operativas de CPU, memoria, solicitudes y latencia para la evaluación del despliegue.

## Productos de demostración

Se crearon cinco productos mediante `POST /api/products`; no se insertaron credenciales ni datos sensibles en el repositorio. Cada alta produjo además un evento `PRODUCT_SAVED` en el servicio de auditoría.

## Comandos de consulta

Las evidencias se obtuvieron mediante AWS CLI con consultas de solo lectura a:

- `aws ecs describe-services`;
- `aws cloudwatch get-metric-statistics`;
- `aws logs filter-log-events`;
- `aws xray get-trace-summaries`.
