#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck source=/dev/null
  source "${ENV_FILE}"
fi

GENERATED_DIR="${GENERATED_DIR:-${MLFLOW_HOME:-${SCRIPT_DIR}/runtime}/generated}"
SRC_CONF="${GENERATED_DIR}/mlflow.conf"
DST_CONF="/etc/nginx/conf.d/mlflow.conf"

if [[ ! -f "${SRC_CONF}" ]]; then
  echo "Missing ${SRC_CONF}"
  echo "Run: bash ${SCRIPT_DIR}/setup_external_nginx_conf.sh"
  exit 1
fi

echo "Installing external nginx config (sudo required)..."
sudo cp "${SRC_CONF}" "${DST_CONF}"
sudo nginx -t
sudo systemctl reload nginx

echo "Installed:"
echo "  ${DST_CONF}"
echo
echo "Quick callback route check:"
echo "  curl -k -I \"https://mlflow.alcf.anl.gov/oauth2/callback?code=test&state=test\""
