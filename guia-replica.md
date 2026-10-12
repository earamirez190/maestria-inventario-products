# Guía de réplica de observabilidad en AWS

Esta guía permite replicar el laboratorio de observabilidad de los microservicios `maestria-inventario-products` y `maestria-inventario-audit` usando AWS CLI, PowerShell, Docker y los archivos de este repositorio.

> **Alcance:** laboratorio académico. El despliegue crea recursos con costo potencial en AWS: RDS MySQL, ECS/Fargate, Application Load Balancer, ECR, CloudWatch y X-Ray. Elimina los recursos cuando termines.

## 1. Arquitectura que se va a replicar

El flujo desplegado es:

```text
Cliente
  |
  v
Application Load Balancer
  |
  v
maestria-inventario-products  --->  maestria-inventario-audit
              |                              |
              +----------> RDS MySQL <-------+

ECS/Fargate + OpenTelemetry Collector
  +--> AWS X-Ray: trazas
  +--> CloudWatch Logs: logs correlacionados
  +--> CloudWatch/ECS/ALB/RDS: métricas
```

Cada solicitud instrumentada debe conservar el contexto W3C Trace Context. Los logs incluyen `trace_id` y las trazas permiten seguir la operación desde `products` hasta `audit` y MySQL.

## 2. Requisitos previos

Instala o verifica lo siguiente:

- AWS CLI v2.
- Docker Desktop iniciado.
- Git.
- PowerShell 7 o Windows PowerShell 5.1.
- Una cuenta AWS con permisos de laboratorio para EC2/VPC, IAM, ECR, ECS, ELB, RDS, Secrets Manager, CloudWatch Logs, CloudWatch Metrics y X-Ray.
- El repositorio clonado localmente.
- Una región AWS y una VPC con al menos dos subredes disponibles.

Configura las credenciales con `aws configure`, AWS SSO o el mecanismo autorizado por el curso. Nunca guardes claves, contraseñas ni tokens en el repositorio.

Abre PowerShell en la carpeta raíz del repositorio:

```powershell
Set-Location "D:\Maestria\Semetre1\Observabilidad\Unidad 2"
```

Comprueba la identidad y la región:

```powershell
aws sts get-caller-identity
aws configure get region
```

Si la segunda orden no devuelve una región, define una para la sesión:

```powershell
$region = "us-east-1"
$env:AWS_DEFAULT_REGION = $region
```

## 3. Identificar la VPC y las subredes

No reutilices los identificadores de otra cuenta. Obtén los valores de tu propia cuenta.

Consultar las VPC predeterminadas de la región:

```powershell
$region = "us-east-1"; $vpcId = aws ec2 describe-vpcs --region $region --filters Name=is-default,Values=true --query "Vpcs[0].VpcId" --output text; $vpcId
```

Consultar las subredes disponibles de esa VPC:

```powershell
aws ec2 describe-subnets --region $region --filters "Name=vpc-id,Values=$vpcId" "Name=state,Values=available" --query "Subnets[].{Id:SubnetId,AZ:AvailabilityZone,PublicIp:MapPublicIpOnLaunch}" --output table
```

Selecciona dos subredes en zonas de disponibilidad distintas. Para el laboratorio se usan subredes públicas porque las tareas Fargate necesitan salida de red sin agregar NAT Gateway. Esta decisión simplifica la práctica, pero no es la configuración recomendada para producción.

Ejemplo de asignación —**reemplaza los valores**—:

```powershell
$subnets = @("subnet-AAAAAAAAAAAAAAAAA", "subnet-BBBBBBBBBBBBBBBBB")
```

Verifica que pertenezcan a la VPC seleccionada:

```powershell
aws ec2 describe-subnets --region $region --subnet-ids $subnets --query "Subnets[].{Id:SubnetId,VPC:VpcId,AZ:AvailabilityZone,State:State}" --output table
```

## 4. Revisar el código antes de desplegar

Comprueba que estás en la raíz del repositorio y que el script existe:

```powershell
Get-ChildItem .\deploy\aws\provision-aws.ps1, .\deploy\aws\otel-collector-config.yaml, .\docker-compose.yml
```

El despliegue principal está en:

- `deploy/aws/provision-aws.ps1`: crea la infraestructura, empaqueta las imágenes y configura ECS.
- `deploy/aws/otel-collector-config.yaml`: recibe OTLP y exporta trazas a X-Ray y señales de diagnóstico a CloudWatch.
- `Dockerfile`: imagen del microservicio de productos.
- `audit-service/Dockerfile`: imagen del microservicio de auditoría.

Obtén un identificador para etiquetar las imágenes:

```powershell
$imageTag = (git rev-parse --short HEAD).Trim()
if ([string]::IsNullOrWhiteSpace($imageTag)) { $imageTag = "replica-$(Get-Date -Format yyyyMMddHHmmss)" }
$imageTag
```

## 5. Ejecutar el despliegue completo

Ejecuta el siguiente comando desde la raíz del repositorio. Sustituye `us-east-1`, `$vpcId` y `$subnets` si elegiste otra región o VPC:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\deploy\aws\provision-aws.ps1 -Region $region -VpcId $vpcId -Subnets $subnets -ImageTag $imageTag
```

El script realiza estas operaciones:

1. Obtiene el ID de la cuenta mediante STS.
2. Crea o reutiliza grupos de seguridad.
3. Crea los roles de ejecución y de tarea de ECS.
4. Genera credenciales de RDS y las guarda en Secrets Manager.
5. Crea la instancia RDS MySQL.
6. Crea los repositorios ECR.
7. Construye y publica las imágenes de `products`, `audit` y el Collector.
8. Crea el clúster, la definición de tarea y el servicio ECS/Fargate.
9. Crea el Application Load Balancer y el target group.
10. Configura CloudWatch Logs y X-Ray.

Espera a que el script muestre el bloque `DESPLEGADO` y la URL pública. La primera creación de RDS puede tardar varios minutos.

## 6. Validar ECS, ALB y RDS

Define las variables del despliegue:

```powershell
$cluster = "maestria-observabilidad-cluster"
$service = "maestria-observabilidad-service"
$albName = "maestria-observabilidad-alb"
$dns = aws elbv2 describe-load-balancers --region $region --names $albName --query "LoadBalancers[0].DNSName" --output text
$dns
```

Confirma que ECS tenga una tarea ejecutándose:

```powershell
aws ecs describe-services --region $region --cluster $cluster --services $service --query "services[0].{Desired:desiredCount,Running:runningCount,Pending:pendingCount,Status:status}" --output table
```

Consulta la salud del target del ALB:

```powershell
$tgArn = aws elbv2 describe-target-groups --region $region --names "maestria-observabilidad-tg" --query "TargetGroups[0].TargetGroupArn" --output text
aws elbv2 describe-target-health --region $region --target-group-arn $tgArn --output table
```

El estado esperado es `healthy`.

Comprueba el endpoint de salud:

```powershell
Invoke-RestMethod "http://$dns/actuator/health" | ConvertTo-Json -Depth 8
```

La respuesta esperada contiene `"status": "UP"` y el componente de MySQL en estado `UP`.

## 7. Generar evidencia funcional y de auditoría

Primero consulta los productos:

```powershell
Invoke-RestMethod "http://$dns/api/products" | ConvertTo-Json -Depth 8
```

Para generar una operación distribuida `products -> audit -> MySQL`, inserta un producto de prueba. Esta orden modifica los datos de la base de datos:

```powershell
$body = @{ name = "Producto réplica OTel"; description = "Registro para validar trazas y auditoría"; price = 125000; quantity = 10 } | ConvertTo-Json; Invoke-RestMethod -Method Post -Uri "http://$dns/api/products" -ContentType "application/json" -Body $body | ConvertTo-Json -Depth 8
```

Genera tráfico de lectura sin insertar más registros:

```powershell
1..100 | ForEach-Object { Invoke-RestMethod "http://$dns/api/products" | Out-Null }; Write-Host "Tráfico generado: 100 solicitudes GET"
```

## 8. Consultar logs correlacionados en CloudWatch Logs Insights

En la consola AWS:

1. Selecciona la región usada en el despliegue.
2. Abre **CloudWatch → Registros → Análisis de registros / Logs Insights**.
3. Selecciona `/ecs/maestria-observabilidad`.
4. Define un intervalo que incluya la prueba.
5. Ejecuta esta consulta:

```text
fields @timestamp, @message
| filter @message like /trace_id/
| sort @timestamp desc
| limit 20
```

La evidencia correcta muestra mensajes de la aplicación junto con `serviceName`, `trace_id` y, según la operación, mensajes como `Products listed` o `Product audit persisted`.

También se puede consultar una ventana pequeña por AWS CLI, aunque Logs Insights es más útil para presentar la evidencia:

```powershell
aws logs filter-log-events --region $region --log-group-name "/ecs/maestria-observabilidad" --filter-pattern '"trace_id"' --max-items 20 --query "events[].message" --output text
```

## 9. Consultar trazas en X-Ray

En la consola AWS:

1. Abre **CloudWatch → Application Signals / Señales de aplicación (APM) → Mapa de registros de seguimiento / Trace map** o **X-Ray → Trace map**.
2. Usa la misma región del despliegue.
3. Selecciona el servicio `maestria-inventario-products`.
4. Abre una traza de `POST /api/products`.
5. Verifica el árbol y la línea de tiempo.

La evidencia esperada contiene:

- Servicio `maestria-inventario-products`.
- Llamada remota a `maestria-inventario-audit`.
- Segmentos `products.save` y `audit.persist`.
- Consultas SQL `INSERT` en RDS MySQL.
- Código HTTP `201` para la creación.
- Duración total y duración individual de cada segmento.

En el mapa de servicios también se deben observar los nodos de `products`, `audit` y la base de datos SQL.

## 10. Consultar métricas de ECS y ALB

Para obtener evidencia de CPU y memoria de la tarea ECS, usa CloudWatch Metrics en la consola o estas consultas CLI. El período y las fechas deben coincidir con el intervalo de la prueba:

```powershell
$end = (Get-Date).ToUniversalTime(); $start = $end.AddMinutes(-15); aws cloudwatch get-metric-statistics --region $region --namespace AWS/ECS --metric-name CPUUtilization --dimensions Name=ClusterName,Value=$cluster Name=ServiceName,Value=$service --statistics Average Maximum --period 60 --start-time $start.ToString("o") --end-time $end.ToString("o") --output table
```

```powershell
$end = (Get-Date).ToUniversalTime(); $start = $end.AddMinutes(-15); aws cloudwatch get-metric-statistics --region $region --namespace AWS/ECS --metric-name MemoryUtilization --dimensions Name=ClusterName,Value=$cluster Name=ServiceName,Value=$service --statistics Average Maximum --period 60 --start-time $start.ToString("o") --end-time $end.ToString("o") --output table
```

Para revisar solicitudes del ALB:

```powershell
$albArn = aws elbv2 describe-load-balancers --region $region --names $albName --query "LoadBalancers[0].LoadBalancerArn" --output text; $albDimension = ($albArn -replace '^arn:aws:elasticloadbalancing:[^:]+:[^:]+:loadbalancer/','').Replace('/','/'); $albDimension
```

La consola de CloudWatch es preferible para ALB porque permite seleccionar fácilmente la dimensión exacta del Load Balancer y mostrar `RequestCount`, `TargetResponseTime` y códigos HTTP.

## 11. Ejecutar el benchmark AWS de solo lectura

El repositorio incluye un benchmark k6 que consulta `GET /api/products` y no llena la base de datos:

```powershell
.\benchmark\run-aws-benchmark.ps1 -BaseUrl "http://$dns" -Duration "1m" -VUs 50
```

Si k6 no está instalado, instálalo siguiendo la documentación oficial de k6 o ejecuta el script en el entorno autorizado por el curso. Guarda el resumen generado en `benchmark/results/aws/` y registra:

- solicitudes totales y solicitudes por segundo;
- porcentaje de fallos;
- p50, p95 y p99;
- CPU y memoria de ECS durante la prueba;
- observaciones de X-Ray y CloudWatch Logs.

Para una comparación local con y sin OpenTelemetry está disponible:

```powershell
.\benchmark\run-benchmark.ps1
```

## 12. Archivos importantes del repositorio

| Archivo | Propósito |
|---|---|
| `deploy/aws/provision-aws.ps1` | Provisiona AWS con AWS CLI y PowerShell. |
| `deploy/aws/otel-collector-config.yaml` | Configuración OTLP del Collector para AWS. |
| `deploy/aws/README.md` | Notas del despliegue AWS. |
| `docker-compose.yml` | Stack local con servicios, Collector, Jaeger, Prometheus, Grafana y Loki. |
| `grafana/dashboards/spring-boot-overview.json` | Dashboard con throughput, errores, latencia, disponibilidad, CPU y Collector. |
| `benchmark/run-benchmark.ps1` | Benchmark local con y sin OTel. |
| `benchmark/run-aws-benchmark.ps1` | Benchmark AWS de lectura. |
| `evidence/aws/observability-2026-10-12.md` | Evidencia de logs, métricas y trazas AWS. |
| `evidence/aws/benchmark-2026-10-12.md` | Resultados del benchmark AWS. |
| `guia-replica.md` | Este instructivo. |

## 13. Problemas frecuentes

### La tarea ECS queda en `PENDING`

Revisa eventos del servicio y logs del Collector:

```powershell
aws ecs describe-services --region $region --cluster $cluster --services $service --query "services[0].events[0:10]" --output table
aws logs describe-log-streams --region $region --log-group-name "/ecs/maestria-observabilidad" --order-by LastEventTime --descending --max-items 10 --output table
```

Las causas habituales son imágenes que no llegaron a ECR, permisos insuficientes del rol de ejecución, subredes sin salida a Internet o un grupo de seguridad incorrecto.

### El ALB responde `503`

Comprueba el estado del target:

```powershell
aws elbv2 describe-target-health --region $region --target-group-arn $tgArn --output table
```

Espera a que esté `healthy` y verifica que el contenedor exponga el puerto esperado.

### No aparecen trazas

Confirma que:

- estás consultando la misma región;
- generaste tráfico después del despliegue;
- el servicio ECS está `RUNNING`;
- los logs del Collector contienen mensajes de recepción/exportación;
- estás buscando en X-Ray para el despliegue AWS, no en el Jaeger local.

### Un panel dice `No data`

Puede significar que no hubo errores durante el intervalo. Cambia el intervalo de tiempo, genera tráfico y verifica el nombre/dimensión de la métrica antes de concluir que existe un fallo.

## 14. Limpieza para evitar costos

Antes de borrar, conserva las capturas, los resultados del benchmark y las trazas necesarias para la entrega. Después identifica exactamente los recursos creados con el prefijo `maestria-observabilidad` y `maestria-inventario`.

El script de provisión no elimina recursos. La limpieza debe hacerse de forma controlada desde la consola o con AWS CLI, respetando dependencias:

1. Detener/eliminar el servicio ECS.
2. Eliminar el ALB y el target group.
3. Eliminar el clúster ECS.
4. Eliminar la instancia RDS y confirmar si se requiere o no snapshot final.
5. Eliminar los repositorios ECR solo después de confirmar que no se necesitan sus imágenes.
6. Eliminar el secreto de Secrets Manager.
7. Eliminar el log group de CloudWatch.
8. Eliminar los grupos de seguridad y roles IAM únicamente si no los usa otro laboratorio.

No ejecutes comandos de borrado sobre una cuenta compartida sin revisar antes los nombres, ARNs y dependencias. Si el laboratorio pertenece a una cuenta institucional, solicita autorización antes de eliminar recursos.

## 15. Evidencia mínima para la entrega

Incluye en el informe:

1. Resultado de `aws sts get-caller-identity` sin exponer credenciales.
2. Servicio ECS `RUNNING` y target group `healthy`.
3. `/actuator/health` con MySQL `UP`.
4. Respuesta de `GET /api/products`.
5. Trace Map de X-Ray con `products`, `audit` y MySQL.
6. Trace Detail de `POST /api/products` con HTTP 201 y segmentos SQL.
7. Consulta de CloudWatch Logs Insights con `trace_id`.
8. Métricas de CPU, memoria, solicitudes y latencia.
9. Dashboard de Grafana local con sus seis paneles.
10. Resultados del benchmark y comparación de latencias.

La réplica se considera correcta cuando se pueden relacionar una misma operación mediante sus trazas, sus logs con `trace_id` y sus métricas de servicio, sin publicar contraseñas, tokens, claves AWS ni valores de Secrets Manager.
