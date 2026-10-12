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
- Despliegue en AWS: `.github/workflows/deploy-aws.yaml` publica la imagen en ECR y actualiza un servicio ECS Fargate existente.

## Docker

- `Dockerfile`: construye la aplicacion Spring Boot con Java 21.
- `docker-compose.yml`: levanta la aplicación, MySQL, Prometheus, Grafana y el stack local de observabilidad.
- Los workflows publican la misma imagen construida desde el Dockerfile a los registros de cada proveedor.

### Publicar la imagen de la aplicacion en Docker Hub

El servicio `app` de Docker Compose usa la imagen `earamirez/maestria-inventario-products:latest`. Para construirla y publicarla, inicia sesion en Docker Hub y ejecuta:

```powershell
docker login
docker compose build app
docker compose push app
```

Esto publica unicamente la imagen de la aplicacion; MySQL, Prometheus, Grafana y SonarQube son imagenes independientes de terceros.

### Despliegue AWS ECS Fargate

El workflow de AWS requiere que el cluster y servicio ECS Fargate, la definición inicial de tarea y la base de datos ya existan. Construye la imagen desde el `Dockerfile`, la publica en el repositorio Docker Hub público `earamirez/maestria-inventario-products` y actualiza el servicio ECS con la etiqueta SHA del commit. No requiere un repositorio ECR.

| Variable | Valor |
| --- | --- |
| `AWS_REGION` | Región AWS donde están los recursos |
| `ECS_CLUSTER` | Nombre del cluster ECS |
| `ECS_SERVICE` | Nombre del servicio ECS Fargate |
| `ECS_CONTAINER_NAME` | Nombre del contenedor de la aplicación en la definición de tarea |

Agrega estos secretos del repositorio GitHub: `AWS_ROLE_TO_ASSUME` con el ARN del rol IAM que confía en GitHub Actions mediante OIDC, `DOCKERHUB_USERNAME` con el usuario de Docker Hub y `DOCKERHUB_TOKEN` con un access token de Docker Hub (no la contraseña de la cuenta). El rol IAM necesita permisos para describir y registrar definiciones de tarea, actualizar y consultar el servicio ECS, y pasar los roles de ejecución/tarea ECS (`iam:PassRole`); ya no requiere permisos para publicar en ECR.

La definición inicial de tarea debe usar Fargate, plataforma Linux x86_64, y exponer el puerto `9090` del contenedor. Configura la URL JDBC, usuario y contraseña de la base de datos en la definición de tarea; almacena credenciales en AWS Secrets Manager y referencia esos secretos desde ECS, no en el repositorio. El servicio Fargate y RDS deben tener conectividad de red entre sí y grupos de seguridad que permitan el puerto de MySQL desde las tareas.

Al completarse correctamente el workflow `CI DevSecOps` en `main`, el workflow de AWS crea las etiquetas `latest` y SHA del commit en Docker Hub, actualiza la imagen del contenedor en la definición de tarea y espera a que el servicio ECS quede estable. También puede iniciarse manualmente desde GitHub Actions.

### Monitoreo con Prometheus y Grafana
- `Prometheus`: Configurado mediante `prometheus.yml` para realizar scraping de las métricas expuestas por Spring Boot Actuator, disponible en `http://localhost:9093`.
- `Grafana`: Incluye un tablero preconfigurado para visualizar el estado, la memoria, el tráfico HTTP y la salud general de la API, disponible en `http://localhost:3002` con usuario `admin` y contraseña `admin`. También tiene las fuentes Loki y Jaeger provisionadas para correlacionar logs y trazas.
- `MySQL`: El puerto externo local es `3310`; dentro de Docker Compose la aplicación continúa conectándose a `mysql:3306`.
- `SonarQube`: Disponible en `http://localhost:9001`.
- `Uso con Docker Compose`: Se puede levantar el entorno ejecutando `docker compose up -d --build`.
- `service-b` (auditoría): disponible en `http://localhost:9094`; dentro de Docker el servicio A lo invoca como `http://service-b:9090`.

- La aplicación expone su API y métricas en `http://localhost:9092` y `http://localhost:9092/actuator/prometheus`.

### Observabilidad OpenTelemetry local

- La aplicación usa el starter de OpenTelemetry para instrumentación automática de Spring Web, JDBC, métricas y logs, además de spans de negocio `products.save` y `products.list`.
- La arquitectura local es `service-a (products) -> service-b (audit) -> MySQL`; al crear un producto, A llama a B por HTTP y B persiste el evento en `product_audit_events`.
- La propagación W3C conserva el mismo `trace_id` entre ambos servicios, sus spans HTTP/JDBC y sus logs.
- Los logs se emiten como JSON y conservan `trace_id` y `span_id` tanto en la salida de la aplicación como en Loki.
- El Collector recibe OTLP por gRPC en `localhost:4317` y HTTP/protobuf en `localhost:4318`; expone sus métricas Prometheus en `localhost:9464` y su healthcheck en `localhost:13133`.
- `Jaeger`: UI en `http://localhost:16686`.
- `Loki`: readiness/API en `http://localhost:3100`.
- Configuración versionada: `observability/otel-collector-config.yaml`, `observability/loki-config.yaml` y `grafana/provisioning/datasources/datasource.yml`.

Para generar una traza local y verla en Jaeger/Grafana:

```powershell
$body = @{ name = 'OTel demo'; quantity = 10; price = 25.0 } | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri http://localhost:9092/api/products `
  -ContentType 'application/json' -Body $body
```

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
