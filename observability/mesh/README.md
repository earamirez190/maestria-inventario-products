# Service mesh básico — Módulo A

La aplicación ya exporta trazas y métricas a nivel de aplicación. Para
observar tráfico L7 entre pods se puede activar Istio/Cloud Service Mesh en un
cluster sandbox. El repositorio deja el recurso de Telemetry separado para no
activar sidecars ni mTLS accidentalmente en un cluster compartido.

## Activación controlada

1. Instalar Istio o habilitar Cloud Service Mesh siguiendo el estándar del
   proyecto.
2. Etiquetar el namespace:

```bash
kubectl label namespace actividad1 istio-injection=enabled --overwrite
```

3. Aplicar `telemetry.yaml` y reiniciar los deployments de la aplicación.
4. Confirmar métricas HTTP L7 y trazas de Envoy antes de ejecutar chaos.

La alternativa GKE recomendada es Dataplane V2/Cloud Service Mesh cuando esté
disponible en el proyecto. La evidencia debe indicar la distribución instalada,
la versión y los pods con sidecar; no se debe afirmar que existe mesh solo por
tener OTel en el código.
