#!/usr/bin/env bash
#
# attacker_bootstrap.sh
# Aprovisionamiento del nodo atacante sobre Amazon Linux 2023.
# Instala las dependencias, materializa el simulador de ataques (inyectado por
# Terraform en base64) y lo ejecuta contra la victima cuando esta disponible.

# Modo estricto de shell (ver victim_bootstrap.sh para el detalle de flags).
set -euo pipefail

# Duplica la salida al log persistente.
exec > >(tee -a /var/log/user-data.log) 2>&1

echo "[attacker_bootstrap] inicio $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# IP privada de la victima (exportada por Terraform antes de este script).
TARGET_IP="${TARGET_IP:-TARGET_IP_PLACEHOLDER}"

# Contenido del simulador Python codificado en base64 (inyectado por Terraform).
ATTACK_SIMULATOR_B64="${ATTACK_SIMULATOR_B64:-}"

# Rutas de instalacion del simulador en la maquina.
INSTALL_DIR="/opt/attacker"
SIMULATOR="${INSTALL_DIR}/attack_simulator.py"

# ===========================================================================
# PASO 1 | Instalacion de dependencias (Python 3, pip, git y requests).
# En Amazon Linux 2023 el gestor de paquetes es dnf. requests se instala como
# paquete del sistema (python3-requests) para evitar el bloqueo PEP 668 que
# afecta a la instalacion global con pip en entornos gestionados.
# ===========================================================================
dnf install -y python3 python3-pip python3-requests git

# ===========================================================================
# PASO 2 | Materializacion del simulador de ataques.
# Se decodifica el base64 recibido y se escribe el fichero Python en disco.
# Asi el nodo es autocontenido y no depende de clonar un repositorio externo.
# ===========================================================================
mkdir -p "$INSTALL_DIR"
if [ -n "$ATTACK_SIMULATOR_B64" ]; then
  echo "$ATTACK_SIMULATOR_B64" | base64 -d >"$SIMULATOR"
else
  echo "[attacker_bootstrap] ERROR: no se recibio el contenido del simulador"
  exit 1
fi

# ===========================================================================
# PASO 3 | Health check del objetivo.
# Espera a que la victima responda HTTP 200 en el puerto 80 antes de atacar.
# curl -w '%{http_code}' extrae solo el codigo HTTP. Timeout de 300 s (fatal:
# sin objetivo no tiene sentido lanzar los ataques).
# ===========================================================================
HEALTH_TIMEOUT=300
HEALTH_ELAPSED=0
until [ "$(curl -s -o /dev/null -w '%{http_code}' "http://${TARGET_IP}:80" || true)" = "200" ]; do
  if [ "$HEALTH_ELAPSED" -ge "$HEALTH_TIMEOUT" ]; then
    echo "[attacker_bootstrap] ERROR: el objetivo ${TARGET_IP}:80 no respondio HTTP 200 en ${HEALTH_TIMEOUT}s"
    exit 1
  fi
  echo "[attacker_bootstrap] esperando disponibilidad de http://${TARGET_IP}:80 (${HEALTH_ELAPSED}s)"
  sleep 3
  HEALTH_ELAPSED=$((HEALTH_ELAPSED + 3))
done

# ===========================================================================
# PASO 4 | Pausa de estabilizacion y ejecucion de la suite de ataque.
# Los 10 s permiten que los buffers de ingesta del SIEM se asienten.
# ===========================================================================
echo "[attacker_bootstrap] objetivo disponible; pausa de estabilizacion (10s)"
sleep 10

TARGET_IP="${TARGET_IP}" python3 "${SIMULATOR}"

echo "[attacker_bootstrap] fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"
