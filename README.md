# 📦 Arquitectura de Inventario Productos

## 馃 Integrante 懃

| Nombre completo                  | Código Estudiante |
|----------------------------------|-------------------|
| Luis Fernando Alvarez            | 0000371905        |
| David Fernando Perez Medina      | 0000407511        |
| Edward Augusto Ramirez Rodriguez | 0000324316        |
| Jorge Antonio Vidal Orozco       | 0000393815        |

## Workflows

-  Ramas principales: develop, laboratory, production 
-  CI/CD: docker.yaml para integración y despliegue.

## Docker

-  Dockerfile: define la construcción de la imagen. 
-  Despliegue: mediante contenedores, publicación en Docker Hub y despliegue en AWS.

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

## 🚀 Beneficios

-  Builder → creación de productos limpia y extensible.
-  Strategy → lógica de negocio flexible y mantenible. 
-  Adapter + DTOs → API segura y desacoplada del dominio. 
-  Clean Architecture → independencia tecnológica, fácil evolución. 
-  CI/CD con Docker → despliegue automatizado y portable.


---
