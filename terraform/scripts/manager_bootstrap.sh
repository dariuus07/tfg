#!/usr/bin/env bash
#
# manager_bootstrap.sh
# Aprovisionamiento del nodo manager sobre Amazon Linux 2023.
# Marcador de posicion: en la Fase 5 instalara Wazuh Manager, Ollama/TinyLlama
# y la integracion custom-ai-telegram. Por ahora solo deja traza de arranque.

# Modo estricto de shell.
set -euo pipefail

# Duplica la salida al log persistente.
exec > >(tee -a /var/log/user-data.log) 2>&1

echo "[manager_bootstrap] placeholder ejecutado en $(date -u +%Y-%m-%dT%H:%M:%SZ)"
