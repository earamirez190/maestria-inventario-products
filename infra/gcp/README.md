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
kubectl apply -f ../../k8s/data-service-serviceaccount.yaml
kubectl apply -f ../../k8s/data-service-configmap.yaml
kubectl apply -f ../../k8s/data-service-service.yaml
kubectl apply -f ../../k8s/data-service-deployment.yaml
kubectl apply -f ../../k8s/service-b-service.yaml
kubectl apply -f ../../k8s/service-b-deployment.yaml
kubectl apply -f ../../k8s/deployment.yaml
```

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
