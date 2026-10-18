# Variante AWS (RDS)

El código de `data-service` soporta `DATABASE_PROVIDER=rds` y una URL MySQL o
PostgreSQL. La provisión AWS queda separada de la rama GCP para no crear
recursos accidentalmente. Usa los scripts existentes en `deploy/aws/` para ECS
y configura como mínimo:

```text
CLOUD_PROVIDER=aws
DATABASE_PROVIDER=rds
DATABASE_URL=postgresql://usuario:password@endpoint-rds:5432/inventorydb
```

La evidencia AWS se considera completa solo después de tener RDS, ECS y un
exportador OTLP/X-Ray funcionando. No se presentan recursos AWS como creados
si no existe una cuenta autorizada.
