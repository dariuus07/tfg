#!/usr/bin/env bash
set -euo pipefail
exec > >(tee -a /var/log/user-data.log) 2>&1

echo "[attacker_bootstrap] placeholder executed at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
