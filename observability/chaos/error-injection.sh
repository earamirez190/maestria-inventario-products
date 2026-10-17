#!/bin/bash
# Inyección simple de errores al 10%: llama al endpoint /items y fuerza 500 en 10% de las llamadas.
URL=${1:-"http://localhost:8000/items/1"}
RATE=100
ERROR_PERCENT=10

for i in $(seq 1 $RATE); do
  if [ $((RANDOM % 100)) -lt $ERROR_PERCENT ]; then
    # Simular error: llamar a endpoint que produce 500 (si existe) o no responder
    curl -s -X GET "$URL?inject_error=true" || true
  else
    curl -s -X GET "$URL" > /dev/null
  fi
  sleep 0.1
done
