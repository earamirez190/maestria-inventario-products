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
- Esta entrega no despliega en Kubernetes, AWS ni Azure.

## Docker

- `Dockerfile`: construye la aplicacion Spring Boot con Java 21.
- `docker-compose.yml`: levanta la aplicacion y MySQL para pruebas locales.
- No se publica imagen en DockerHub ni se despliega en un cluster.

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
