#!/usr/bin/env bash
set -euo pipefail
exec > >(tee -a /var/log/user-data.log) 2>&1

echo "[attacker_bootstrap] inicio $(date -u +%Y-%m-%dT%H:%M:%SZ)"

export DEBIAN_FRONTEND=noninteractive

TARGET_IP="${TARGET_IP:-TARGET_IP_PLACEHOLDER}"
REPO_URL="https://github.com/dariuus07/tfg.git"
REPO_DIR="/opt/tfg"
SIMULATOR="${REPO_DIR}/terraform/scripts/attack_simulator.py"

apt-get update -y
apt-get install -y python3 python3-pip python3-requests git

if [ -d "${REPO_DIR}/.git" ]; then
  git -C "${REPO_DIR}" pull --ff-only
else
  git clone "${REPO_URL}" "${REPO_DIR}"
fi

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

echo "[attacker_bootstrap] objetivo disponible; pausa de estabilizacion (10s)"
sleep 10

TARGET_IP="${TARGET_IP}" python3 "${SIMULATOR}"

echo "[attacker_bootstrap] fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"
