#!/usr/bin/env bash
#
# victim_bootstrap.sh
# Aprovisionamiento del nodo victima sobre Amazon Linux 2023 (ECS-optimized).
# Docker viene preinstalado en la AMI; aqui solo se habilita, se instala el
# agente de Wazuh y se despliega OWASP Juice Shop.

# Modo estricto: -e aborta ante error, -u ante variable no definida,
# pipefail propaga errores dentro de tuberias (curl | gpg, etc.).
set -euo pipefail

# Duplica toda la salida al log persistente ademas de a la consola.
exec > >(tee -a /var/log/user-data.log) 2>&1

echo "[victim_bootstrap] inicio $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# IP privada del Wazuh Manager. Terraform la exporta como variable de entorno
# antes de ejecutar este script; el valor por defecto es solo una salvaguarda.
WAZUH_MANAGER_IP="${WAZUH_MANAGER_IP:-MANAGER_IP_PLACEHOLDER}"

# ===========================================================================
# PASO 1 | Docker (ya preinstalado en la AMI ECS-optimized).
# Solo se habilita y arranca el servicio; no se instala nada.
# ===========================================================================
systemctl enable --now docker

# Desactiva el agente de ECS: la AMI lo trae para clusteres ECS, que aqui no se
# usan. Se detiene para evitar consumo y ruido en los logs. El "|| true" evita
# que el modo estricto aborte si la unidad no existe.
systemctl disable --now ecs || true

# ===========================================================================
# PASO 2 | Instalacion del agente de Wazuh desde el repositorio YUM oficial.
# ===========================================================================

# Importa la clave GPG del repositorio para verificar la firma de los paquetes.
rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH

# Registra el repositorio YUM de Wazuh (rama 4.x). El heredoc entre comillas
# ('REPO') impide la expansion de variables dentro del bloque.
cat >/etc/yum.repos.d/wazuh.repo <<'REPO'
[wazuh]
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
name=EL-$releasever - Wazuh
baseurl=https://packages.wazuh.com/4.x/yum/
protect=1
REPO

# Instala el agente. La variable WAZUH_MANAGER es leida por el paquete durante
# la instalacion y fija automaticamente la IP del manager en ossec.conf.
WAZUH_MANAGER="$WAZUH_MANAGER_IP" dnf install -y wazuh-agent

# Recarga systemd, habilita el agente en el arranque y lo inicia para que
# establezca la sesion cifrada con el manager en el puerto 1514.
systemctl daemon-reload
systemctl enable --now wazuh-agent

# ===========================================================================
# PASO 3 | Barrera de sincronizacion.
# Espera a que el agente establezca (ESTAB) la sesion TCP con el manager antes
# de exponer la aplicacion vulnerable, para no perder las primeras alertas.
# Timeout de 300 s para no bloquear cloud-init indefinidamente.
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
# PASO 4 | Despliegue del contenedor OWASP Juice Shop.
# Publica el puerto interno 3000 en el puerto 80 del host. La comprobacion
# previa hace la operacion idempotente (no recrea el contenedor si ya existe).
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
