#!/bin/bash
# Inyecta 200ms de latencia en la interfaz eth0 (ejemplo para entorno local/VM o contenedor con privilegios)
IFACE=${1:-eth0}
DELAY_MS=200

sudo tc qdisc add dev "$IFACE" root netem delay ${DELAY_MS}ms || echo "tc qdisc add failed or already applied"

echo "Latencia de ${DELAY_MS}ms aplicada en $IFACE"

# Para remover:
# sudo tc qdisc del dev $IFACE root
