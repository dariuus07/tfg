#!/usr/bin/env bash
#
# victim_bootstrap.sh
# Aprovisionamiento del nodo victima (OWASP Juice Shop + Wazuh Agent).
# Ejecutado por cloud-init como root en el primer arranque de la instancia.

# ---------------------------------------------------------------------------
# Modo estricto de shell:
#   -e  aborta el script ante cualquier comando que devuelva un codigo != 0.
#   -u  aborta si se referencia una variable no definida.
#   -o pipefail  propaga el error de cualquier etapa de una tuberia (pipe).
# Garantiza que un fallo de instalacion no deje la maquina en estado a medias.
# ---------------------------------------------------------------------------
set -euo pipefail

# Redirige stdout y stderr a un fichero de log persistente ademas de a la
# consola, para poder auditar el aprovisionamiento con `tail -f`.
exec > >(tee -a /var/log/user-data.log) 2>&1

echo "[victim_bootstrap] inicio $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Evita que apt lance dialogos interactivos (debconf) durante la instalacion
# desatendida; imprescindible al ejecutarse sin terminal (cloud-init).
export DEBIAN_FRONTEND=noninteractive

# Direccion IP privada del Wazuh Manager. Se resuelve por variable de entorno;
# si no se ha inyectado todavia, se conserva un marcador que sera sustituido
# por Terraform (templatefile) en una fase posterior.
WAZUH_MANAGER_IP="${WAZUH_MANAGER_IP:-MANAGER_IP_PLACEHOLDER}"

# ===========================================================================
# PASO 1 | Actualizacion de repositorios e instalacion de dependencias base.
# ===========================================================================
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release apt-transport-https

# ===========================================================================
# PASO 2 | Instalacion de Docker Engine desde el repositorio oficial de Docker.
# Se prefiere el repositorio oficial frente al paquete de Ubuntu para obtener
# una version soportada y actualizada.
# ===========================================================================

# Directorio con permisos 0755 donde se almacenaran las claves GPG de apt.
install -m 0755 -d /etc/apt/keyrings

# Descarga e importa la clave publica de firma del repositorio de Docker.
# --batch --yes hace la operacion idempotente (sobrescribe sin preguntar).
curl -fsSL https://download.docker.com/linux/ubuntu/gpg |
  gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Registra el repositorio de Docker firmado con la clave anterior, resolviendo
# dinamicamente la arquitectura (amd64/arm64) y el nombre de la version de
# Ubuntu (p.ej. "noble") en tiempo de ejecucion.
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  >/etc/apt/sources.list.d/docker.list

# Refresca indices ya con el repositorio de Docker disponible e instala el
# motor, la CLI, containerd y los plugins de buildx y compose.
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Habilita el servicio para que arranque con el sistema y lo inicia ahora.
systemctl enable docker
systemctl start docker

# ===========================================================================
# PASO 3 | Instalacion del agente de Wazuh desde el repositorio oficial 4.x.
# La variable de entorno WAZUH_MANAGER es leida por el paquete .deb durante
# la instalacion y fija automaticamente la IP del manager en ossec.conf.
# ===========================================================================
curl -fsSL https://packages.wazuh.com/key/GPG-KEY-WAZUH |
  gpg --batch --yes --dearmor -o /usr/share/keyrings/wazuh.gpg
chmod a+r /usr/share/keyrings/wazuh.gpg

echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" \
  >/etc/apt/sources.list.d/wazuh.list

apt-get update -y
WAZUH_MANAGER="$WAZUH_MANAGER_IP" apt-get install -y wazuh-agent

# Recarga la definicion de unidades systemd, habilita el agente en el arranque
# y lo inicia para que establezca la sesion cifrada contra el manager (1514).
systemctl daemon-reload
systemctl enable wazuh-agent
systemctl start wazuh-agent

# ===========================================================================
# PASO 4 | Barrera de sincronizacion.
# Espera activa hasta confirmar que el agente ha establecido (ESTAB) la sesion
# TCP con el manager en el puerto 1514, garantizando que la telemetria esta
# operativa antes de exponer la aplicacion vulnerable. Se aplica un timeout de
# 300 s para no bloquear cloud-init de forma indefinida si el manager no responde.
# ===========================================================================
SYNC_TIMEOUT=300
SYNC_ELAPSED=0
until ss -tan | grep -q "${WAZUH_MANAGER_IP}:1514.*ESTAB"; do
  if [ "$SYNC_ELAPSED" -ge "$SYNC_TIMEOUT" ]; then
    echo "[victim_bootstrap] ADVERTENCIA: timeout esperando sesion con el manager; se continua igualmente"
    break
  fi
  echo "[victim_bootstrap] esperando conexion del agente con ${WAZUH_MANAGER_IP}:1514 (${SYNC_ELAPSED}s)"
  sleep 3
  SYNC_ELAPSED=$((SYNC_ELAPSED + 3))
done

# ===========================================================================
# PASO 5 | Despliegue del contenedor OWASP Juice Shop.
# Se publica el puerto interno 3000 del contenedor en el puerto 80 del host.
# La comprobacion previa hace la operacion idempotente: no recrea el contenedor
# si ya existe (p.ej. tras un reinicio de la instancia).
# ===========================================================================
if ! docker ps -a --format '{{.Names}}' | grep -q '^juice-shop$'; then
  docker run -d \
    --name juice-shop \
    --restart unless-stopped \
    -p 80:3000 \
    bkimminich/juice-shop:latest
else
  echo "[victim_bootstrap] el contenedor juice-shop ya existe; se omite docker run"
fi

echo "[victim_bootstrap] fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"
