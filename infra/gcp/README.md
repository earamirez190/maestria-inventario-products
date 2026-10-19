# Infraestructura GCP del laboratorio

Este módulo es IaC para un proyecto propio de laboratorio. Crea GKE con
Workload Identity, Artifact Registry, Cloud SQL MySQL y la identidad de
`data-service`. No se debe aplicar contra proyectos compartidos sin revisar
costos y permisos.

## Aplicación

```bash
cd infra/gcp
cp terraform.tfvars.example terraform.tfvars
# Editar terraform.tfvars y cambiar la contraseña
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Después de aplicar, obtener credenciales y desplegar los manifiestos:

```bash
gcloud container clusters get-credentials actividad1-gke \
  --zone us-central1-a --project mydemo-505323
kubectl apply -f ../../k8s/namespace.yaml
kubectl apply -f ../../k8s/otel-collector-serviceaccount.yaml
kubectl apply -f ../../k8s/otel-collector-configmap.yaml
kubectl apply -f ../../k8s/otel-collector-service.yaml
kubectl apply -f ../../k8s/otel-collector-deployment.yaml
kubectl apply -f ../../k8s/data-service-serviceaccount.yaml
kubectl apply -f ../../k8s/data-service-configmap.yaml
kubectl apply -f ../../k8s/data-service-service.yaml
kubectl apply -f ../../k8s/data-service-deployment.yaml
kubectl apply -f ../../k8s/service-b-service.yaml
kubectl apply -f ../../k8s/service-b-deployment.yaml
kubectl apply -f ../../k8s/deployment.yaml
```

Las imágenes de esta rama se publican para `linux/amd64` y los manifiestos
usan sus digests para evitar errores de plataforma en GKE. Si se reconstruyen,
usar `docker buildx build --platform linux/amd64 --provenance=false --sbom=false`
y publicar nuevamente antes de aplicar los deployments.

El secreto `database-secret` debe existir antes del despliegue. Créalo desde
un gestor de secretos o con `kubectl create secret`; no se debe versionar una
contraseña real ni modificar `data-service-secret.example.yaml` con secretos.
La clave debe contener `username`, `password` y `root-password`: las dos
primeras las usa `data-service` contra Cloud SQL y la última el MySQL interno
que usa `app/service-b` para sus datos de auditoría.

Antes de `service-b` y `app`, aplica también el almacenamiento MySQL interno:

```bash
kubectl apply -f ../../k8s/mysql-pvc.yaml
kubectl apply -f ../../k8s/mysql-service.yaml
kubectl apply -f ../../k8s/mysql-deployment.yaml
kubectl apply -f ../../k8s/configmap.yaml
```

Después de crear la instancia de Cloud SQL, inicializar el esquema de
`data-service` en `inventorydb` con el script SQL compatible con el motor
MySQL. La tabla `products` debe existir antes de probar
`/api/observability/data/products`; no se debe confundir con el MySQL interno
que usa `app/service-b` para auditoría.

Para el sandbox de dos nodos se dejan una réplica por servicio y solicitudes de
CPU reducidas. Antes de experimentar caos, confirmar:

```bash
kubectl get pods -n actividad1
kubectl get svc maestria-inventario-products -n actividad1
```
