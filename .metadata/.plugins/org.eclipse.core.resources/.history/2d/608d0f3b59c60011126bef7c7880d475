# Benchmark AWS — 2026-10-12

## Alcance

- Endpoint: `GET /api/products`
- Objetivo: medir el servicio desplegado en ECS Fargate detrás del ALB.
- Método: k6 con 50 VUs constantes durante 1 minuto.
- Tipo de carga: solo lectura, para no llenar RDS con productos de prueba.
- OTel: habilitado en el despliegue productivo.

## Resultado k6

| Métrica | Resultado |
|---|---:|
| Solicitudes | 12.201 |
| Solicitudes/segundo | 202,697 |
| Errores HTTP | 0,00 % |
| Checks correctos | 100,00 % |
| p50 | 212,560 ms |
| p95 | 443,115 ms |
| p99 | 620,978 ms |

## Métricas AWS observadas

Durante la ventana del benchmark, CloudWatch reportó:

- ECS `CPUUtilization`: promedio 24,51 %, máximo 71,50 %.
- ECS `MemoryUtilization`: promedio entre 33,02 % y 34,79 %; máximo observado 34,91 %.
- ALB `TargetResponseTime`, en el periodo agregado de cinco minutos: promedio 122,85 ms y máximo 1.033 ms.
- ALB `RequestCount`: 7.868 solicitudes en el periodo que contiene la mayor parte de la ejecución.

La métrica de k6 es la referencia principal para p50/p95/p99 porque mide desde el cliente hasta el ALB; las métricas del ALB se publican agregadas en ventanas de CloudWatch y pueden quedar divididas entre periodos.

## Reproducción

```powershell
.\benchmark\run-aws-benchmark.ps1 -Vus 50 -Duration 1m
```

El script usa `GET` intencionalmente. El benchmark comparativo con y sin OTel para el flujo de escritura está en `benchmark\run-benchmark.ps1` y se ejecuta localmente para evitar crear miles de registros en RDS.
