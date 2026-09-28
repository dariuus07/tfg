#!/usr/bin/env bash
#
# manager_bootstrap.sh
# Aprovisionamiento del nodo manager sobre Amazon Linux 2023:
# Wazuh Manager (instalacion desatendida) + Ollama/TinyLlama + la integracion
# custom-ai-telegram (SIEM -> IA -> Telegram).

# Modo estricto de shell.
set -euo pipefail

# Duplica la salida al log persistente.
exec > >(tee -a /var/log/user-data.log) 2>&1

echo "[manager_bootstrap] inicio $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Credenciales y parametros inyectados por Terraform como variables de entorno.
TELEGRAM_TOKEN="${TELEGRAM_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"
OLLAMA_MODEL="${OLLAMA_MODEL:-tinyllama}"
# Contenido del script de integracion, inyectado en base64 por Terraform.
CUSTOM_INTEGRATION_B64="${CUSTOM_INTEGRATION_B64:-}"

# Rutas de la integracion dentro del arbol de Wazuh.
INTEGRATION_BIN="/var/ossec/integrations/custom-ai-telegram"
INTEGRATION_CONF="/var/ossec/integrations/custom-ai-telegram.conf"
OSSEC_CONF="/var/ossec/etc/ossec.conf"

# ===========================================================================
# PASO 1 | Dependencias del sistema para la integracion Python.
# ===========================================================================
dnf install -y python3 python3-pip python3-requests

# ===========================================================================
# PASO 2 | Instalacion desatendida de Wazuh (all-in-one: manager, indexer y
# dashboard). --ignore-check omite la comprobacion estricta de sistema.
# Idempotente: si /var/ossec ya existe, se omite la instalacion.
# ===========================================================================
if [ ! -d /var/ossec ]; then
  curl -sO https://packages.wazuh.com/4.9/wazuh-install.sh
  bash ./wazuh-install.sh -a -i --ignore-check
else
  echo "[manager_bootstrap] Wazuh ya esta instalado; se omite wazuh-install.sh"
fi

# ===========================================================================
# PASO 3 | Instalacion de Ollama y descarga del modelo local.
# ===========================================================================
if ! command -v ollama >/dev/null 2>&1; then
  curl -fsSL https://ollama.com/install.sh | sh
fi
systemctl enable --now ollama

# Espera activa a que la API de Ollama responda antes de descargar el modelo.
OLLAMA_TIMEOUT=180
OLLAMA_ELAPSED=0
until curl -sf http://127.0.0.1:11434/api/tags >/dev/null; do
  if [ "$OLLAMA_ELAPSED" -ge "$OLLAMA_TIMEOUT" ]; then
    echo "[manager_bootstrap] ADVERTENCIA: la API de Ollama no respondio en ${OLLAMA_TIMEOUT}s"
    break
  fi
  sleep 3
  OLLAMA_ELAPSED=$((OLLAMA_ELAPSED + 3))
done
ollama pull "${OLLAMA_MODEL}"

# ===========================================================================
# PASO 4 | Despliegue del script de integracion (decodificado de base64).
# ===========================================================================
if [ -z "$CUSTOM_INTEGRATION_B64" ]; then
  echo "[manager_bootstrap] ERROR: no se recibio el contenido de la integracion"
  exit 1
fi
echo "$CUSTOM_INTEGRATION_B64" | base64 -d >"$INTEGRATION_BIN"
# El ejecutable pertenece a root y al grupo wazuh, con permisos 0750: el
# proceso integratord (que corre como usuario wazuh) puede ejecutarlo.
chown root:wazuh "$INTEGRATION_BIN"
chmod 750 "$INTEGRATION_BIN"

# ===========================================================================
# PASO 5 | Fichero de configuracion de la integracion (credenciales/endpoints).
# Permisos 0640 root:wazuh: solo root y el grupo wazuh pueden leer el token.
# El heredoc SIN comillas permite expandir las variables de entorno.
# ===========================================================================
cat >"$INTEGRATION_CONF" <<CONF
{
  "telegram_token": "${TELEGRAM_TOKEN}",
  "telegram_chat_id": "${TELEGRAM_CHAT_ID}",
  "ollama_url": "http://127.0.0.1:11434/api/generate",
  "ollama_model": "${OLLAMA_MODEL}"
}
CONF
chown root:wazuh "$INTEGRATION_CONF"
chmod 640 "$INTEGRATION_CONF"

# ===========================================================================
# PASO 6 | Registro de la integracion en ossec.conf.
# Inserta el bloque <integration> antes del cierre </ossec_config> solo si no
# existe ya, para que la operacion sea idempotente. Dispara para nivel >= 7.
# ===========================================================================
if ! grep -q "custom-ai-telegram" "$OSSEC_CONF"; then
  TMP_CONF="$(mktemp)"
  awk '/<\/ossec_config>/ && !done {
        print "  <integration>";
        print "    <name>custom-ai-telegram</name>";
        print "    <level>7</level>";
        print "    <alert_format>json</alert_format>";
        print "  </integration>";
        done=1
      }
      { print }' "$OSSEC_CONF" >"$TMP_CONF"
  mv "$TMP_CONF" "$OSSEC_CONF"
  chown root:wazuh "$OSSEC_CONF"
  chmod 660 "$OSSEC_CONF"
fi

# ===========================================================================
# PASO 7 | Reinicio del manager para activar el demonio integratord.
# ===========================================================================
systemctl restart wazuh-manager

echo "[manager_bootstrap] fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"
