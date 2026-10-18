# Despliegue AWS de observabilidad

El script `provision-aws.ps1` crea una instalación de laboratorio en `us-east-1` con:

- RDS MySQL privado.
- Tres repositorios ECR: productos, auditoría y OpenTelemetry Collector.
- ECS Fargate con los dos microservicios y el collector como sidecar.
- Application Load Balancer público para `products`.
- CloudWatch Logs y exportación de trazas a AWS X-Ray.

Las credenciales de RDS se generan durante la ejecución y se almacenan en AWS Secrets Manager. No se deben guardar contraseñas en el repositorio.

Ejecución desde la raíz del proyecto:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\deploy\aws\provision-aws.ps1 -ImageTag <commit>
```

La configuración actual es para laboratorio: usa la VPC predeterminada, subredes públicas y `assignPublicIp=ENABLED` para que Fargate pueda descargar imágenes sin NAT Gateway. Para producción se recomienda una VPC dedicada, subredes privadas, NAT o VPC endpoints, HTTPS con ACM, autoscaling y una política IAM limitada.
