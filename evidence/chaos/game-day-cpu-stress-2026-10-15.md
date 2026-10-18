# Game Day local: estrés de CPU

## Objetivo y alcance

Ejecutar un experimento de caos acotado sobre `GET /api/products` para observar la disponibilidad y la latencia de la API cuando el equipo comparte CPU con una carga intensiva.

- **Hipótesis:** con dos workers de CPU durante 30 segundos, la API seguirá respondiendo; el p95 se mantendrá por debajo de 100 ms y la tasa de errores por debajo del 1 %. Estos son límites de este experimento, no SLOs definidos para producción.
- **Radio de impacto:** equipo local; dos workers de `stress-ng`; un endpoint de lectura; sin escritura de datos de negocio.
- **Criterios de interrupción:** detener la carga si la API deja de responder o aparecen errores consecutivos. Cada solicitud tuvo un timeout de 10 segundos.
- **Recuperación:** la carga termina automáticamente a los 30 segundos; comprobar el health check y detener la aplicación local.

## Entorno y procedimiento ejecutado

- Windows con WSL2 Ubuntu 24.04, 8 vCPU visibles y `stress-ng` 0.17.06.
- Aplicación Spring Boot 3.3.5 con Java 21, iniciada en el puerto 9092 con el perfil `test` y H2 en memoria. Se usó temporalmente un Gradle init script para añadir `testRuntimeClasspath` a `bootRun`, ya que H2 está declarado como dependencia de test.
- Docker Engine no estaba disponible. Por eso, la prueba no levantó MySQL, `service-b` ni el stack de observabilidad; el perfil test deshabilita el cliente de auditoría y OpenTelemetry.
- Se calentó el endpoint y se midió una línea base de 60 solicitudes secuenciales. A continuación, se lanzó la carga y se siguió consultando el mismo endpoint hasta terminar:

```powershell
wsl -d Ubuntu-24.04 -- stress-ng --cpu 2 --cpu-load 100 --timeout 30s --metrics-brief
```

La medición de cada solicitud se hizo con `Invoke-RestMethod` y un cronómetro de PowerShell. `stress-ng` reportó 104.629 operaciones, 30,01 segundos de ejecución y cero workers fallidos.

## Resultados observados

| Condición | Solicitudes | Errores HTTP/timeout | Mediana | p95 | Máximo |
| --- | ---: | ---: | ---: | ---: | ---: |
| Línea base | 60 | 0 | 3,05 ms | 3,75 ms | 43,08 ms |
| CPU: 2 workers, 30 s | 228 | 0 | 4,28 ms | 7,53 ms | 31,25 ms |

El p95 aumentó aproximadamente un **101 %** (3,75 → 7,53 ms) y la mediana un **40 %** (3,05 → 4,28 ms). No hubo errores y ambas mediciones quedaron por debajo del umbral experimental de 100 ms. El máximo aislado fue mayor en la línea base; no debe interpretarse como una degradación causada por el experimento.

## Reflexión y remediación propuesta

La debilidad observada es sensibilidad de latencia a la contención de CPU: el servicio se mantuvo disponible, pero el p95 se duplicó bajo una carga acotada. Esto no demuestra una caída ni identifica el punto exacto de saturación. Además, esta prueba presionó la CPU de la VM WSL mientras la aplicación corría en Windows; no aisló la CPU del proceso o de un contenedor. En `docker-compose.yml` los servicios no tienen cuotas ni reservas de CPU configuradas.

Como siguiente remediación, definir límites y reservas de CPU para cada servicio en el entorno de despliegue y monitorear CPU/throttling junto con p95 y errores HTTP, con alertas vinculadas a SLOs acordados. En Compose/ECS conviene repetir el experimento aplicando la carga dentro del contenedor de la aplicación y con una carga concurrente representativa. Esta ejecución tampoco valida tolerancia a fallos de MySQL ni la llamada síncrona de auditoría a `service-b`; deben cubrirse en un Game Day independiente, con latencia o indisponibilidad inyectada al servicio B y límites de tiempo explícitos en el cliente.

Para cerrar el ciclo anti-frágil, usar estas mediciones como referencia local, acordar los SLOs y alertas del servicio, implementar la remediación y repetir el mismo experimento. Considerar la acción completa solo después de comparar la nueva ejecución con los límites acordados; registrar por separado los experimentos pendientes sobre dependencias.

## Limitaciones

Prueba local de baja carga y corta duración, con solicitudes secuenciales y base de datos H2 en memoria. Los resultados son evidencia de esta ejecución, no una garantía de rendimiento bajo concurrencia, producción o fallos de dependencias. Para aumentar el valor del siguiente Game Day: activar Docker, usar el stack completo, generar concurrencia controlada y comparar las métricas de Prometheus con objetivos de servicio definidos.
