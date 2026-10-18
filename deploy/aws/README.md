# Laboratorio AWS ECS + FIS

La preparación se adapta a los servicios ECS ya existentes del laboratorio en `us-east-2`; no crea otra VPC, RDS, ALB ni cluster. **No se han ejecutado cambios ni experimentos en AWS.** El script `prepare-fis-existing-ecs.ps1` modifica IAM, registra nuevas revisiones de task definition, inicia un nuevo deployment de los tres servicios, asegura al menos dos tareas por servicio y crea alarmas CloudWatch. Revísalo antes de ejecutarlo.

## Cambios de arquitectura preparados

- Cluster: `prd-maestriainventario-ecs`; servicio de productos: `td-maestriainventario-inventario-products-api-prd-service-wkkqqol1`; contenedor de productos: `maestria-inventario-products-api`.
- Servicio de auditoría: `td-maestriainventario-audi-api-prd-service-4c4nxx0x`; contenedor de auditoría: `maestria-inventario-audi-api`.
- Servicio data-service: `td-maestriainventario-service-api-prod-service-onouq3k1`; contenedor: `maestria-inventario-service-api`.
- El script prepara las tres task definitions existentes para FIS (`pidMode=task`, `enableFaultInjection`, SSM Agent sidecar) y propaga `ChaosTarget=products|audit|data-service` a las tareas. No cambia las direcciones internas: valida que `PRODUCT_AUDIT_URL` y `DATA_SERVICE_URL` en la task definition de productos apunten a endpoints privados alcanzables, y que data-service use `SPRING_PROFILES_ACTIVE=data-service`.
- Se requieren al menos **2 tareas por servicio** para que detener una tarea no apague toda su capacidad. El script eleva `desiredCount` a 2 cuando está por debajo; esto aumenta coste. No reduce una capacidad superior a 2.

## Requisitos y revisión previa

1. AWS CLI configurado para la cuenta autorizada, en `us-east-2`; permisos de lectura de ECS, IAM, ELB y CloudWatch para las comprobaciones previas.
2. Para ejecutar el script, la identidad necesita además permisos para actualizar los servicios ECS/task definitions, etiquetar servicios, crear/actualizar roles y políticas IAM, pasar roles a ECS/SSM, administrar alarmas CloudWatch y leer la metadata del ALB. El script no elimina servicios ni bases de datos, pero sí inicia despliegues nuevos.
3. El task role existente debe ser modificable. Se le agrega permiso de registrar el sidecar SSM; se crea un rol SSM managed-instance con `AmazonSSMManagedInstanceCore` y un rol de experimento FIS limitado al cluster/tareas etiquetadas. La identidad que inicia FIS debe tener permisos para crear/consultar/iniciar/detener templates y `iam:PassRole` solo al rol de experimento.
4. Las tareas necesitan salida de red a los endpoints de Systems Manager y acceso de lectura a la imagen pública del sidecar. ECS Exec debe estar deshabilitado. Tras el deployment, valida el registro SSM del sidecar y que no haya comandos pendientes antes de experimentar.
5. `provision-aws.ps1` es otro aprovisionador para una topología nueva y conserva IDs de VPC/subredes de otra región; **no lo ejecutes para este cluster**. Usa `prepare-fis-existing-ecs.ps1` solo después de revisar sus efectos y parámetros.

Para el despliegue del data-service añade al workflow las variables `ECS_DATA_SERVICE=td-maestriainventario-service-api-prod-service-onouq3k1`, `ECS_DATA_CONTAINER_NAME=maestria-inventario-service-api` y `DATA_SERVICE_URL`. Esta última debe ser la URL base privada que productos pueda resolver y alcanzar, con esquema y puerto (no `localhost`); por ejemplo, el DNS de ECS Service Connect si está configurado. Permite productos→data-service por el puerto `9090` y ambos servicios→MySQL por `3306`. Data-service reutiliza la imagen de productos con el perfil Spring `data-service`.

Configura las variables del workflow `.github/workflows/deploy-aws.yaml` con los recursos existentes: `AWS_REGION=us-east-2`, `ECS_CLUSTER=prd-maestriainventario-ecs`, `ECS_SERVICE=td-maestriainventario-inventario-products-api-prd-service-wkkqqol1`, `ECS_CONTAINER_NAME=maestria-inventario-products-api`, `ECS_AUDIT_SERVICE=td-maestriainventario-audi-api-prd-service-4c4nxx0x` y `ECS_AUDIT_CONTAINER_NAME=maestria-inventario-audi-api`. El workflow publica ambas imágenes en Docker Hub; crea los repositorios requeridos y asegúrate de que ECS pueda descargarlas.

Antes de preparar FIS, valida que los nombres y el endpoint privado de auditoría de la task definition correspondan al entorno:

```powershell
.\deploy\aws\prepare-fis-existing-ecs.ps1 `
  -Region us-east-2 `
  -ClusterName prd-maestriainventario-ecs `
  -ProductsServiceName td-maestriainventario-inventario-products-api-prd-service-wkkqqol1 `
  -ProductsContainerName maestria-inventario-products-api `
  -AuditServiceName td-maestriainventario-audi-api-prd-service-4c4nxx0x `
  -AuditContainerName maestria-inventario-audi-api
```

Este comando **modifica AWS**: crea/actualiza roles y alarmas, registra nuevas revisiones de task definitions y despliega los tres servicios con al menos dos tareas. No lo ejecutes hasta revisar permisos, ambas URL privadas, el costo adicional y la ventana de deployment. No inicia experimentos FIS. Revisa los ARNs que imprime y valida salud/SSM de todas las tareas antes de crear los experimentos.

## Plantillas FIS

**Alcance actual del script:** aunque la nota del párrafo anterior conserva la descripción de la versión de dos servicios, esta versión procesa productos, auditoría y data-service; los parámetros `DataServiceName` y `DataContainerName` ya tienen los valores ECS indicados arriba. La comprobación valida ambas direcciones privadas antes de modificar recursos.

La preparación del script cubre los tres servicios, pero las plantillas JSON incluidas en este directorio todavía apuntan únicamente a `ChaosTarget=audit`; no inicies una prueba contra data-service reutilizando esos archivos sin revisar y cambiar el target. La llamada al script mostrada arriba usa por defecto los nombres de los tres servicios.

`chaos/audit-cpu-stress.json`, `chaos/audit-network-latency.json`, `chaos/audit-network-blackhole-rds.json` y `chaos/audit-stop-task.json` son plantillas JSON de solicitud de FIS. Reemplaza **todas** las apariciones de `REPLACE_WITH_...` en una copia, nunca en el original:

- `REPLACE_WITH_ECS_CLUSTER_ARN`: ARN real del cluster.
- `REPLACE_WITH_FIS_EXPERIMENT_ROLE_ARN`: ARN del rol FIS impreso por el script de preparación.
- `REPLACE_WITH_CHAOS_STOP_ALARM_5XX_ARN` y `REPLACE_WITH_CHAOS_STOP_ALARM_UNHEALTHY_ARN`: ARNs de las alarmas de protección creadas por el aprovisionador.

Las cuatro seleccionan como máximo una tarea `ChaosTarget=audit`, adicionalmente filtrada por ARN de cluster. Las acciones CPU/red duran como máximo 60 segundos; la acción stop-task es inmediata:

- CPU: 50%, un worker.
- Latencia: 250 ms + 25 ms de jitter, 100% de los flujos IPv4 desde `ALL` (no incluye IPv6; AWS documenta requisito ECS Agent ≥1.100.0 para `flowsPercent`, verifica soporte de la plataforma Fargate usada).
- Blackhole: TCP/3306 egress solo en una tarea `audit` (corta su acceso a RDS; `products` no es target).
- Stop task: detiene una tarea audit inmediatamente; ECS debe reponerla mientras la otra tarea continúa disponible. No requiere SSM ni tiene parámetro de duración.

El blackhole y la latencia son acciones a nivel de tarea/red, no equivalen a Chaos Mesh `HTTPChaos`. La latencia con `sources=ALL` puede afectar otros flujos de red de esa tarea además del tráfico a RDS. AWS FIS no tiene una acción equivalente que inyecte respuestas HTTP 500 aleatorias (por ejemplo, 10%); esa prueba necesita un fault proxy dedicado o una inyección en la aplicación, fuera de estas plantillas. No se han cambiado los YAML de Chaos Mesh existentes: son evidencia/referencia Kubernetes.

La latencia y el blackhole son fallos de red de tarea: `sources=ALL` no filtra por endpoint; retrasa el egress audit→RDS y también las respuestas de audit a products, por lo que puede elevar la latencia observada por products. No son equivalentes a Chaos Mesh `HTTPChaos`. Cada plantilla referencia alarmas CloudWatch para detener FIS si el ALB observa una respuesta 5xx de products o un target de products no saludable. Confirma que ambas alarmas existan y estén `OK` antes de iniciar el experimento. `aws:ecs:stop-task` detiene una tarea ECS sin SSM; la capacidad deseada 2 permite que ECS reponga una tarea, pero no evita errores transitorios.

## Validación y ejecución manual (no ejecutadas)

Primero revisa el template y el alcance en la consola de AWS FIS: usa **Preview target** y confirma que aparece exactamente una tarea audit del cluster esperado y ninguna tarea products. No hay un `dry-run` de `start-experiment`; no lo uses como mecanismo de vista previa. Comprueba las tareas y etiquetas:

```powershell
aws ecs describe-services --region us-east-2 --cluster prd-maestriainventario-ecs --services td-maestriainventario-inventario-products-api-prd-service-wkkqqol1 td-maestriainventario-audi-api-prd-service-4c4nxx0x --query 'services[].{name:serviceName,desired:desiredCount,running:runningCount}'
aws ecs list-tasks --region us-east-2 --cluster prd-maestriainventario-ecs --service-name td-maestriainventario-audi-api-prd-service-4c4nxx0x --desired-status RUNNING
aws ecs list-tasks --region us-east-2 --cluster prd-maestriainventario-ecs --service-name td-maestriainventario-inventario-products-api-prd-service-wkkqqol1 --desired-status RUNNING
aws fis get-experiment-template --id <template-id>
```

Una vez revisados permisos, target preview, plantilla, dashboards y ventana de laboratorio, crea el template con el JSON de copia ya completado y conserva su ID:

```powershell
$clusterArn = '<ARN real de prd-maestriainventario-ecs>'
$fisRoleArn = '<ARN de rol FIS impreso por prepare-fis-existing-ecs.ps1>'
$alarm5xxArn = '<ARN de alarma 5xx impreso por prepare-fis-existing-ecs.ps1>'
$alarmUnhealthyArn = '<ARN de alarma unhealthy impreso por prepare-fis-existing-ecs.ps1>'
Get-ChildItem .\deploy\aws\chaos\audit-*.json | Where-Object { $_.Name -notlike '*.ready.json' } | ForEach-Object {
    $json = (Get-Content -Raw $_.FullName).Replace('REPLACE_WITH_ECS_CLUSTER_ARN', $clusterArn).Replace('REPLACE_WITH_FIS_EXPERIMENT_ROLE_ARN', $fisRoleArn).Replace('REPLACE_WITH_CHAOS_STOP_ALARM_5XX_ARN', $alarm5xxArn).Replace('REPLACE_WITH_CHAOS_STOP_ALARM_UNHEALTHY_ARN', $alarmUnhealthyArn)
    [IO.File]::WriteAllText($_.FullName.Replace('.json', '.ready.json'), $json, (New-Object Text.UTF8Encoding($false)))
}
aws fis create-experiment-template --cli-input-json file://deploy/aws/chaos/audit-cpu-stress.ready.json
aws fis start-experiment --experiment-template-id <template-id>
aws fis stop-experiment --id <experiment-id>
```

Repite `create-experiment-template` con una sola plantilla por experimento. `stop-experiment` es la parada manual; la reversión automática de latencia/blackhole depende de que la acción llegue a su duración límite. No lances otra prueba hasta que FIS indique estado terminal y ECS muestre ambas capacidades sanas. Los JSON `*.ready.json` se ignoran por Git; elimínalos al terminar el laboratorio.

## Observabilidad y recuperación

- CloudWatch Logs: grupo `/ecs/maestria-observabilidad`; filtra streams `products`, `audit`, `otel-collector` y `amazon-ssm-agent`.
- CloudWatch/ECS: CPU/memoria y running/desired count por servicio; ALB target health/5xx/latencia para products; RDS CPU/conexiones. El aprovisionador crea alarmas de parada para ALB 5xx y targets products no saludables; FIS detiene el experimento si alguna entra en `ALARM`.
- X-Ray: revisa service map, trazas y spans `products.audit` / `audit.persist` para correlacionar efecto y recuperación.
- Si algo no se recupera, detén el experimento, confirma que el SSM document/command terminó y que el servicio recuperó `runningCount == desiredCount`. Los fallos de tarea son reemplazados por ECS; conserva la revisión sana de task definition y restáurala mediante `ecs update-service` si un cambio de despliegue, no la inyección, dejó el servicio degradado. No borres RDS/secretos ni roles como primera respuesta.

Referencias oficiales: [AWS FIS ECS task actions y sidecar SSM](https://docs.aws.amazon.com/fis/latest/userguide/ecs-task-actions.html), [parámetros/permisos FIS ECS](https://docs.aws.amazon.com/fis/latest/userguide/fis-actions-reference.html#ecs-actions-reference), [targets y filtros FIS](https://docs.aws.amazon.com/fis/latest/userguide/targets.html), [ECS Service Connect](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-connect.html).
