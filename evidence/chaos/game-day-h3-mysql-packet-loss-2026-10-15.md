# Game Day H3: pérdida de paquetes hacia MySQL

**Fecha:** 2026-10-15
**Resultado:** criterio numérico de éxito aprobado en esta ejecución; no se encontraron retries de aplicación.

## Hipótesis

Con una pérdida aleatoria del 30 % en la red entre la aplicación y MySQL, `GET /api/products` (`getAllProducts`) mantendrá más de 95 % de éxito gracias a retries con backoff exponencial.

## Entorno y aislamiento

- Docker Engine 29.7.2, servicio Spring Boot en el contenedor `inventario-products-app` y MySQL 8.0.46 en `inventario-products-mysql`.
- Se verificó la URL de conexión de la app: `jdbc:mysql://mysql:3306/maestria_inventario_products`.
- Ambos contenedores estaban en la red Compose `maestria-inventario-products_default`; IP de la app `172.19.0.4`, IP de MySQL `172.19.0.2`.
- Antes de la inyección, el Actuator de la aplicación reportó la base `MySQL` como `UP`.
- `tc netem` no está disponible en el kernel de Docker Desktop de este equipo (`Specified qdisc kind is unknown`). Para evitar modificar interfaces del host, se usó un contenedor temporal `nicolaka/netshoot` unido al namespace de red de la app y reglas `iptables` con módulo `statistic`.
- La regla afectó únicamente paquetes TCP con destino `172.19.0.2:3306` en salida y paquetes TCP desde `172.19.0.2:3306` en entrada. No afectó el acceso HTTP de las pruebas al servicio ni otros destinos.
- Se configuró un timeout de 20 segundos en cada solicitud del generador de carga; esto es un límite del cliente de prueba, no una configuración nueva de la aplicación.

## Procedimiento

Se ejecutaron 120 solicitudes `GET /api/products` con 8 trabajadores concurrentes en condición base. Después se aplicó pérdida probabilística de 30 % en ambos sentidos y se repitió la misma carga. Cada cadena de firewall contó tanto los paquetes descartados como los que continuaron, permitiendo calcular la pérdida observada:

| Sentido | Paquetes descartados | Paquetes no descartados | Pérdida medida |
| --- | ---: | ---: | ---: |
| App → MySQL:3306 | 487 | 1.101 | 30,67 % |
| MySQL:3306 → app | 480 | 1.113 | 30,13 % |

MySQL registró el contador global `Com_select` en 392 antes de la carga pareada y 635 al terminar. El incremento de consultas confirma que las lecturas se atendieron a través de MySQL durante la prueba.

## Resultados

| Condición | Solicitudes | HTTP 200 | Éxito | Errores no-200 | HTTP 5xx | Mediana | p95 | Máximo |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Base, sin pérdida | 120 | 120 | 100 % | 0 | 0 | 8,74 ms | 42,67 ms | 56,52 ms |
| Pérdida 30 % en ambos sentidos | 120 | 120 | 100 % | 0 | 0 | 2.127,82 ms | 9.393,03 ms | 12.792,09 ms |

La carga con pérdida completó en 57.156 ms frente a 211 ms en la carga base. En esta muestra, el éxito fue 100 %, por encima del umbral de 95 %, pero con degradación muy marcada de latencia.

## Evaluación de la hipótesis

- **Disponibilidad observada:** el criterio cuantitativo de más de 95 % se cumplió (120/120 solicitudes exitosas) bajo la tasa de pérdida medida.
- **Causa esperada, no demostrada:** el éxito no demuestra retries de aplicación ni backoff exponencial. `getAllProducts` llama directamente a `repository.findAll()` en `ProductService`; la persistencia usa JDBC/MySQL, no un cliente HTTP hacia la base. El sistema operativo/TCP retransmite segmentos perdidos, lo cual puede explicar respuestas exitosas a costa de latencia elevada. No existe una política de retry de aplicación configurada para esta ruta.
- **Debilidad revelada:** disponibilidad aparente alta bajo una muestra corta, pero latencia p95 de 9,39 s. Con un presupuesto HTTP inferior, más carga o persistencia de la pérdida, las solicitudes podrían expirar y acumular trabajo/conexiones. El resultado no garantiza éxito superior a 95 % fuera de esta ejecución.

## Remediación recomendada

1. Acordar un presupuesto de latencia para `GET /api/products`; configurar timeouts coherentes en el pool Hikari, el driver MySQL/Connector-J, Spring/Tomcat y el balanceador/cliente.
2. Medir y alertar sobre latencia p95/p99, errores, conexiones Hikari activas/pendientes y timeouts de MySQL. No usar solo tasa de éxito para evaluar degradación.
3. Si se requieren retries, implementarlos de forma acotada solo para errores transitorios de lectura, con backoff exponencial, jitter y límite total dentro del presupuesto de la solicitud. Evitar retries ilimitados o en múltiples capas, que pueden amplificar carga cuando MySQL está degradado.
4. Repetir con varias duraciones y volúmenes, y con objetivos de latencia y éxito acordados. La tasa de pérdida aplicada se limita a paquetes entre la app y el endpoint MySQL observado.

## Recuperación y limpieza

Las reglas temporales `H3_CHAOS_OUT` y `H3_CHAOS_IN` se eliminaron en un bloque de limpieza garantizada. Se comprobó que las cadenas `INPUT`/`OUTPUT` volvieron a sus políticas `ACCEPT`, no quedó regla `H3_CHAOS`, y el `qdisc` de `eth0` permanece como `noqueue` (el experimento no lo modificó). Tras retirar la inyección, la aplicación y MySQL siguieron saludables, Actuator reportó `health=UP` y Hikari `active=0`.
