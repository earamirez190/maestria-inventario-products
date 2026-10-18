# Game Day local: re-ejecución de hipótesis de resiliencia

**Fecha:** 2026-10-15
**Alcance:** simulación local del servicio de productos; no se hicieron cambios funcionales en la aplicación ni se ejecutaron acciones contra AWS.

## Resultado ejecutivo

| Hipótesis | Resultado local | Evaluación |
| --- | --- | --- |
| H1: latencia de persistencia de 2 s, timeout HTTP controlado y pool protegido | La escritura tardó aproximadamente 2 s y devolvió `201 Created`; 12 escrituras concurrentes completaron sin errores. No apareció un timeout HTTP. | **Parcial; hipótesis de timeout refutada para el código/configuración probados.** No se agotó el pool en esta carga acotada. |
| H2: saturación de CPU, scale-out ECS antes de 90 s y errores 5xx < 1 % | En la prueba local hubo 0 errores y 0 respuestas 5xx durante 360 lecturas tanto sin carga como con estrés de CPU. | **Disponibilidad local observada; autoscaling no probado.** La infraestructura del repositorio no configura Container Insights ni una política/objetivo de autoscaling ECS. |
| H3: pérdida de paquetes del 30 % hacia la base de datos y éxito de lecturas > 95 % | En el primer intento no ejecutada porque solo había H2. Reejecutada después contra MySQL Docker: 120/120 GET exitosos con ~30 % de pérdida en ambos sentidos; p95 de 9,39 s. | **Umbral de disponibilidad cumplido en esta muestra; backoff de aplicación no demostrado y latencia degradada.** Ver `game-day-h3-mysql-packet-loss-2026-10-15.md`. |

## Entorno de ejecución

- Spring Boot 3.3.5 y Java 21, puerto local 9092, perfil `test`, base H2 en memoria.
- Docker Engine no estaba disponible. Por tanto, no se ejecutaron MySQL, ECS, Fargate, Container Insights, Prometheus del stack ni `service-b`.
- La H2 de prueba es una base embebida; las consultas y escrituras no cruzan una interfaz de red.
- `stress-ng` 0.17.06 corrió en WSL2 Ubuntu 24.04, que reportó 8 CPU visibles. La aplicación se ejecutó en Windows; el estrés compitió por recursos del mismo equipo, pero no impuso una cuota de CPU al proceso o a un contenedor de la aplicación.
- La definición generada por `deploy/aws/provision-aws.ps1` asigna `cpu = '1024'` y `memory = '2048'` a la tarea Fargate. El script no crea ni configura Container Insights, un scalable target de Application Auto Scaling o una política de scale-out.

## H1 — retraso artificial de persistencia en `saveProduct`

**Hipótesis:** con 2.000 ms añadidos en la persistencia, el servicio impone un timeout estricto, responde 504/408 y no agota el pool.

**Procedimiento:** se inició la app con H2, un trigger temporal `BEFORE INSERT` que espera 2.000 ms y un pool Hikari de máximo 10 conexiones. El trigger y la configuración de ejecución fueron temporales y se retiraron al terminar; no se modificó el código de producción. Se midió una escritura individual y luego 12 solicitudes POST concurrentes. Se consultaron las métricas de conexiones Hikari expuestas por Actuator durante la carga.

| Medición | Resultado |
| --- | ---: |
| POST individual | `201 Created`, 2.018 ms |
| POST concurrentes | 12 de 12 `201 Created`; 0 errores; 4.134 ms de tiempo total |
| Pico de conexiones activas Hikari | 9 de 10 |
| Pico de conexiones pendientes | 0 |

**Conclusión:** la escritura no aplicó un timeout de 2 segundos: esperó la latencia y respondió con éxito después de ella. La expectativa de 504/408 **no se cumple** con el comportamiento actual. El pool tampoco se agotó en este volumen; esto no demuestra que resista cargas mayores ni que el pool de ECS tenga el mismo comportamiento.

**Remediación:** establecer timeouts finitos y coordinados para adquisición de conexión, conexión/lectura del driver y transacción; decidir y manejar explícitamente el estado HTTP al vencer el presupuesto de la solicitud. La aplicación captura excepciones genéricas y las transforma en 500, por lo que se requiere un handler específico para timeout. Si se opta por 504, documentar que es la semántica deseada por el API; 408 normalmente indica que expiró la espera de la solicitud del cliente. Repetir con la misma latencia y carga, verificando respuesta, conexiones activas/pendientes y recuperación del pool.

## H2 — carga de CPU y lecturas `getAllProducts`

**Hipótesis:** al saturar el límite de CPU de la tarea ECS, ECS escala antes de 90 s y mantiene 5xx por debajo de 1 %.

**Procedimiento local:** se enviaron tres rondas de 120 GET concurrentes (8 trabajadores × 15 peticiones) en condición base y tres rondas iguales mientras `stress-ng` ejecutaba 8 workers a 100 % durante 30 s. La carga terminó correctamente con 8 workers aprobados y 0 fallidos.

| Condición y ronda | Peticiones | Errores de transporte | 5xx | Mediana | p95 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Base 1 | 120 | 0 | 0 | 2,70 ms | 35,41 ms |
| Base 2 | 120 | 0 | 0 | 2,63 ms | 11,98 ms |
| Base 3 | 120 | 0 | 0 | 2,16 ms | 17,98 ms |
| Estrés 1 | 120 | 0 | 0 | 1,91 ms | 12,12 ms |
| Estrés 2 | 120 | 0 | 0 | 1,10 ms | 8,40 ms |
| Estrés 3 | 120 | 0 | 0 | 1,78 ms | 36,11 ms |

**Conclusión:** en las 360 lecturas de cada condición la tasa observada de 5xx fue 0 %, inferior al umbral de 1 %. Las latencias variaron entre rondas y no mostraron una degradación consistente bajo esta simulación. Esto no prueba el autoscaling: no se ejecutó una tarea ECS, no se alcanzó el límite de CPU de Fargate ni se midió el tiempo de detección/scale-out. Además, el provisioning actual no configura las capacidades de autoscaling requeridas por la hipótesis.

**Remediación:** habilitar Container Insights y configurar ECS Service Auto Scaling con capacidad mínima/máxima, target tracking o una política de step scaling y métricas/alarmas adecuadas. Definir qué señal y ventana medirán los 90 segundos; validarlo en un entorno AWS de pruebas porque esta latencia de escala no puede demostrarse con un stress local.

## H3 — pérdida de paquetes hacia la base de datos

**Hipótesis:** con 30 % de pérdida de paquetes hacia la base de datos, las lecturas `getAllProducts` mantienen más de 95 % de éxito gracias a retries con backoff exponencial.

**Resultado de ejecución inicial:** no ejecutada en el primer intento porque solo estaba disponible H2 embebida. La re-ejecución posterior con Docker/MySQL y el resultado medido se documentan en `game-day-h3-mysql-packet-loss-2026-10-15.md`; sus resultados sustituyen la limitación inicial que sigue siendo válida únicamente para aquel primer intento.

**Evidencia de diseño:** `getAllProducts` llama directamente a `repository.findAll()` y no contiene una política de retries. `ProductAuditClient` solo participa al guardar, captura `RestClientException` y registra una advertencia; tampoco reintenta. Además, ese cliente HTTP no es la ruta de lectura de productos ni reemplaza retries JDBC hacia MySQL.

**Remediación:** probar contra MySQL en una red aislada y aplicar `tc netem` solo al flujo hacia la base de datos. Antes, definir retries acotados con backoff exponencial y jitter solo para errores transitorios de lectura, con un presupuesto total menor al timeout HTTP. Para escrituras, agregar idempotencia antes de reintentar para evitar duplicados. Medir el éxito de GET, latencia, reconexiones y saturación del pool; considerar aprobada la hipótesis únicamente si el éxito observado supera 95 % durante la condición especificada.

## Limpieza y limitaciones

Se detuvo la aplicación y el proceso de estrés, se retiraron los archivos temporales del trigger y de la configuración, y se verificó que Hikari regresó a 0 conexiones activas/pendientes con máximo 10 y que el health check quedó `UP`. No se modificó el estado del sistema de colas de red (`tc`).

Estas mediciones caracterizan una simulación local pequeña, con H2 y sin la topología ECS. No sustituyen una prueba de MySQL, un Game Day de red ni una validación de autoscaling en AWS.
