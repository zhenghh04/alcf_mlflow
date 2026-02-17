#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
USER_NAME="$(whoami)"
SYSTEMD_DIR="/etc/systemd/system"
SERVER_DIR="${SCRIPT_DIR}"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck source=/dev/null
  source "${ENV_FILE}"
fi

GENERATED_DIR="${GENERATED_DIR:-${MLFLOW_HOME:-${SCRIPT_DIR}/runtime}/generated}"

SRC_MLFLOW="${SCRIPT_DIR}/systemd/mlflow-globus.service"
SRC_OAUTH="${SCRIPT_DIR}/systemd/oauth2-proxy.service"
if [[ ! -f "${SRC_MLFLOW}" || ! -f "${SRC_OAUTH}" ]]; then
  SRC_MLFLOW="${SCRIPT_DIR}/mlflow-globus.service"
  SRC_OAUTH="${SCRIPT_DIR}/oauth2-proxy.service"
fi
TMP_MLFLOW="/tmp/mlflow-globus.service"
TMP_OAUTH="/tmp/oauth2-proxy.service"

if [[ ! -f "${GENERATED_DIR}/oauth2-proxy.cfg" ]]; then
  echo "Missing ${GENERATED_DIR}/oauth2-proxy.cfg"
  echo "Run: bash ${SCRIPT_DIR}/setup_globus_auth.sh"
  exit 1
fi

sed -e "s|REPLACE_WITH_VM_USERNAME|${USER_NAME}|g" \
    -e "s|REPLACE_WITH_SERVER_DIR|${SERVER_DIR}|g" \
    -e "s|REPLACE_WITH_GENERATED_DIR|${GENERATED_DIR}|g" \
  "${SRC_MLFLOW}" > "${TMP_MLFLOW}"
sed -e "s|REPLACE_WITH_VM_USERNAME|${USER_NAME}|g" \
    -e "s|REPLACE_WITH_SERVER_DIR|${SERVER_DIR}|g" \
    -e "s|REPLACE_WITH_GENERATED_DIR|${GENERATED_DIR}|g" \
  "${SRC_OAUTH}" > "${TMP_OAUTH}"

echo "Installing systemd units (sudo required)..."
sudo cp "${TMP_MLFLOW}" "${SYSTEMD_DIR}/mlflow-globus.service"
sudo cp "${TMP_OAUTH}" "${SYSTEMD_DIR}/oauth2-proxy.service"
sudo systemctl daemon-reload
sudo systemctl enable --now mlflow-globus
sudo systemctl enable --now oauth2-proxy

echo "Installed and started:"
echo "  mlflow-globus.service"
echo "  oauth2-proxy.service"
echo
echo "Check status:"
echo "  sudo systemctl status mlflow-globus"
echo "  sudo systemctl status oauth2-proxy"
