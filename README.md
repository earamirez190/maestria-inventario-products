# Arquitectura de Inventario Productos

## Integrantes

| Nombre completo                  | Código Estudiante |
|----------------------------------|-------------------|
| Luis Fernando Alvarez            | 0000371905        |
| David Fernando Perez Medina      | 0000407511        |
| Edward Augusto Ramirez Rodriguez | 0000324316        |
| Jorge Antonio Vidal Orozco       | 0000393815        |

## Workflows

- Ramas principales: `develop`, `laboratory`, `main`.
- CI y DevSecOps: `.github/workflows/ci.yml`.
- El pipeline ejecuta pruebas con MySQL, construye el JAR, construye la imagen Docker y ejecuta Trivy.
- Despliegue en GCP: `.github/workflows/deploy.yaml` publica la imagen en Artifact Registry y actualiza GKE.
- Despliegue en AWS: `.github/workflows/deploy-aws.yaml` publica las imágenes de productos y auditoría en Docker Hub y actualiza los tres servicios ECS Fargate: productos, auditoría y data-service.

## Docker

- `Dockerfile`: construye la aplicacion Spring Boot con Java 21.
- `docker-compose.yml`: levanta productos, auditoría, data-service, MySQL, Prometheus, Grafana y el stack local de observabilidad.
- Los workflows de GCP y AWS tienen destinos y configuración independientes; el workflow de AWS publica imágenes distintas para productos y auditoría.

### Publicar la imagen de la aplicacion en Docker Hub

El servicio `app` de Docker Compose usa la imagen `earamirez/maestria-inventario-products:latest`. Para construirla y publicarla, inicia sesion en Docker Hub y ejecuta:

```powershell
docker login
docker compose build app
docker compose push app
```

Esto publica unicamente la imagen de la aplicacion; MySQL, Prometheus, Grafana y SonarQube son imagenes independientes de terceros.

### Despliegue AWS ECS Fargate

El workflow de AWS requiere que el cluster y los tres servicios ECS Fargate (productos, auditoría y data-service), sus definiciones de tarea y la base de datos ya existan. Construye y publica las imágenes `earamirez/maestria-inventario-products` y `earamirez/maestria-inventario-audit` con la etiqueta SHA del commit. Productos y data-service usan la misma imagen de productos; el workflow configura el perfil `data-service` para el servicio de datos. Actualiza los tres servicios y espera a que estén estables. No requiere un repositorio ECR. Para crear la arquitectura de laboratorio ECS con servicios separados y preparar experimentos AWS FIS, consulta [`deploy/aws/README.md`](deploy/aws/README.md).

| Variable | Valor |
| --- | --- |
| `AWS_REGION` | `us-east-2` |
| `ECS_CLUSTER` | `prd-maestriainventario-ecs` |
| `ECS_SERVICE` | `td-maestriainventario-inventario-products-api-prd-service-wkkqqol1` |
| `ECS_CONTAINER_NAME` | `maestria-inventario-products-api` |
| `ECS_AUDIT_SERVICE` | `td-maestriainventario-audi-api-prd-service-4c4nxx0x` |
| `ECS_AUDIT_CONTAINER_NAME` | `maestria-inventario-audi-api` |
| `ECS_DATASERVICE_SERVICE` | `td-maestria-inventario-service-api-prod-service-onouq3k1` |
| `ECS_SERVICE_CONTAINER_NAME` | `maestria-inventario-service-api` |
| `DATA_SERVICE_URL` | URL base privada de data-service alcanzable desde productos, incluyendo esquema y puerto |

Agrega estos secretos del repositorio GitHub: `AWS_ROLE_TO_ASSUME` con el ARN del rol IAM que confía en GitHub Actions mediante OIDC, `DOCKERHUB_USERNAME` con el usuario de Docker Hub y `DOCKERHUB_TOKEN` con un access token de Docker Hub (no la contraseña de la cuenta). Crea previamente los repositorios Docker Hub de productos y auditoría y permite que ECS descargue ambas imágenes. El rol IAM necesita permisos para describir y registrar definiciones de tarea, actualizar y consultar los tres servicios ECS, y pasar los roles de ejecución/tarea ECS (`iam:PassRole`); ya no requiere permisos para publicar en ECR.

Las tareas deben usar Fargate y exponer el puerto `9090` en sus respectivos contenedores. Configura `DATA_SERVICE_URL` con la dirección privada real de data-service (por ejemplo, el nombre DNS de Service Connect si ya está configurado); no uses `localhost` ni una dirección pública. La configuración de descubrimiento y los grupos de seguridad deben permitir productos→data-service por el puerto `9090` y ambos servicios→MySQL por el puerto `3306`. Configura la URL JDBC en ECS y almacena las credenciales en AWS Secrets Manager, no en el repositorio. Para el laboratorio FIS, revisa los prerrequisitos, guardrails, costes y comandos en `deploy/aws/README.md`; preparar el repositorio no ejecuta ni autoriza experimentos en AWS.

Al completarse correctamente el workflow `CI DevSecOps` en `main`, el workflow de AWS crea las etiquetas `latest` y SHA del commit para ambas imágenes en Docker Hub, actualiza productos, auditoría y data-service y espera a que los tres servicios ECS queden estables. También puede iniciarse manualmente desde GitHub Actions.

### Monitoreo con Prometheus y Grafana
- `Prometheus`: Configurado mediante `prometheus.yml` para realizar scraping de las métricas expuestas por Spring Boot Actuator en productos, auditoría y data-service, disponible en `http://localhost:9093`.
- `Grafana`: Incluye el tablero `Inventario · Observabilidad E2E` con seis paneles: throughput, errores 5xx, latencia promedio, disponibilidad 2xx, CPU por microservicio y errores del Collector. Está disponible en `http://localhost:3002` con usuario `admin` y contraseña `admin`. También tiene las fuentes Loki y Jaeger provisionadas para correlacionar logs y trazas.
- `MySQL`: El puerto externo local es `3310`; dentro de Docker Compose la aplicación continúa conectándose a `mysql:3306`.
- `SonarQube`: Disponible en `http://localhost:9001`.
- `Uso con Docker Compose`: Se puede levantar el entorno ejecutando `docker compose up -d --build`.
- `service-b` (auditoría): disponible en `http://localhost:9094`; dentro de Docker el servicio A lo invoca como `http://service-b:9090`.
- `data-service`: disponible desde el host en `http://localhost:9095`; dentro de Docker Compose escucha en `data-service:9090`. Usa la misma imagen de productos con el perfil `data-service`; productos solicita `GET /data/analytics/{productId}` al guardar, sin cambiar el JSON de respuesta pública del POST. La llamada tiene timeout y es fail-open: si data-service no responde, se registra un warning y la creación del producto se conserva.

- La aplicación expone su API y métricas en `http://localhost:9092` y `http://localhost:9092/actuator/prometheus`.

### Observabilidad OpenTelemetry local

- La aplicación usa el starter de OpenTelemetry para instrumentación automática de Spring Web, JDBC, métricas y logs, además de spans de negocio `products.save` y `products.list`.
- La arquitectura local es `products -> audit` y `products -> data-service`, con ambos servicios accediendo a MySQL; al crear un producto, A llama a B para persistir el evento de auditoría y a C para consultar la analítica del producto.
- La propagación W3C conserva el mismo `trace_id` entre ambos servicios, sus spans HTTP/JDBC y sus logs.
- Los logs se emiten como JSON y conservan `trace_id` y `span_id` tanto en la salida de la aplicación como en Loki.
- El Collector recibe OTLP por gRPC en `localhost:4317` y HTTP/protobuf en `localhost:4318`; expone las métricas de la aplicación en `localhost:9464`, sus métricas internas en `localhost:8888` y su healthcheck en `localhost:13133`.
- `Jaeger`: UI en `http://localhost:16686`.
- `Loki`: readiness/API en `http://localhost:3100`.
- Configuración versionada: `observability/otel-collector-config.yaml`, `observability/loki-config.yaml` y `grafana/provisioning/datasources/datasource.yml`.

Para generar una traza local y verla en Jaeger/Grafana:

```powershell
$body = @{ name = 'OTel demo'; quantity = 10; price = 25.0 } | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri http://localhost:9092/api/products `
  -ContentType 'application/json' -Body $body
```

### Benchmark de overhead OTel

El benchmark reproducible usa k6 con 50 usuarios concurrentes por un minuto y compara dos ejecuciones del mismo flujo `POST /api/products`: una con el SDK OTel deshabilitado y otra con OTel habilitado. Durante cada ejecución captura p50, p95, p99, tasa de error, CPU y memoria de `service-a` y `service-b`.

Requiere tener k6 instalado y el stack local levantado. Para ejecutarlo:

```powershell
.\benchmark\run-benchmark.ps1
```

Los resultados quedan en `benchmark/results/summary.csv` y `benchmark/results/summary.json` (la carpeta está ignorada por Git). Se pueden usar parámetros más cortos para una validación rápida, por ejemplo `.\benchmark\run-benchmark.ps1 -Vus 10 -Duration 30s`.

## Calidad y Seguridad (DevSecOps)
- `SonarQube`: Análisis estático de código para medir deuda técnica, cobertura y code smells (configurado en sonar-project.properties).
- `Trivy`: Escaneo de vulnerabilidades (CVEs) en las imágenes de Docker generadas durante la etapa de CI en GitHub Actions.

Flujo implementado:

```text
Commit -> GitHub -> GitHub Actions -> Gradle tests -> Build JAR -> Docker image -> Trivy scan
```

## Estructura de Paquetes Base

- **application** → Casos de uso / Lógica de negocio
- **domain** → Entidades y Contratos/Interfaces
- **infrastructure** → Implementaciones: Controladores REST, Persistencia en memoria

### Domain
La capa de dominio es el corazón de la aplicación.
- **Entidad principal**: Product
- **Interfaz del Repositorio (Contrato)**: Aplicando el Principio de Inversión de Dependencias, la capa de Dominio o Aplicación no debe saber cómo se guardan los datos, solo qué operaciones están disponibles.

### Infrastructure
Aquí se crean las clases que implementan las interfaces del dominio. Ejemplo: `InMemoryProductRepository`.

### Infrastructure / Web
El controlador REST recibe peticiones HTTP, las envía al servicio y devuelve respuestas JSON.  
Los DTOs (`ProductRequest`, `ProductResponse`) viven en esta capa para aislar el dominio de la API pública.

### Capa de Aplicación

Para mantener la arquitectura limpia:
- El **Controlador REST** no debe conectarse directamente al repositorio.
- Creamos una capa intermedia (**Application**) con servicios que consumen `ProductRepository`.
- Se aplica nuevamente la Inversión de Dependencias inyectando la interfaz por constructor.

---

## Principios SOLID y Clean Architecture

- **S - Responsabilidad Única**:
  - `Product` solo maneja el estado del producto.
  - `ProductRepository` define cómo interactuar con el almacenamiento.
  - `InMemoryProductRepository` se encarga de la lógica específica de guardar en memoria.

- **D - Inversión de Dependencias**:  
  Los Casos de Uso dependen de la abstracción `ProductRepository`, no de la implementación concreta.

- **Arquitectura Limpia**:  
  Si mañana decides usar PostgreSQL o MongoDB, solo creas una nueva clase en infraestructura (ej. `PostgresProductRepository`) que implemente la misma interfaz. No se toca la lógica de negocio.

---

## Patrones aplicados

- **Patrón Creacional: Builder**  
  Para construir objetos `Product` de forma limpia y legible.
  ```java
  new ProductBuilder().name("Mouse").price(10.0).build();

- **Patrón Comportamiento: Strategy**  
  Para reglas de negocio dinámicas (ej. descuentos).
  Cada estrategia se encapsula en una clase distinta, cumpliendo Open/Closed.


- **Patrón Estructural: Adapter**
  Traduce objetos de la web a dominio y viceversa mediante DTOs y Mappers.
  Mantiene las capas aisladas y evita exponer entidades de dominio directamente.

## Beneficios

-  Builder: creacion de productos limpia y extensible.
-  Strategy: logica de negocio flexible y mantenible.
-  Adapter + DTOs: API segura y desacoplada del dominio.
-  Clean Architecture: independencia tecnologica y facil evolucion.
-  CI y DevSecOps: validacion automatica, construccion reproducible y escaneo de vulnerabilidades.

---
