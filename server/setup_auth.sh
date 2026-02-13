#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}. Copy from .env.example first."
  exit 1
fi

# shellcheck source=/dev/null
source "${ENV_FILE}"

if [[ -z "${MLFLOW_AUTH_CONFIG_PATH:-}" ]]; then
  echo "MLFLOW_AUTH_CONFIG_PATH is not set in server/.env."
  exit 1
fi

if [[ -z "${MLFLOW_AUTH_ADMIN_PASSWORD:-}" || "${MLFLOW_AUTH_ADMIN_PASSWORD}" == "CHANGE_ME_WITH_STRONG_PASSWORD" ]]; then
  echo "Set a strong MLFLOW_AUTH_ADMIN_PASSWORD in server/.env before running setup_auth.sh."
  exit 1
fi

mkdir -p "$(dirname "${MLFLOW_AUTH_CONFIG_PATH}")"

cat > "${MLFLOW_AUTH_CONFIG_PATH}" <<EOF
[mlflow]
default_permission = ${MLFLOW_AUTH_DEFAULT_PERMISSION}
database_uri = ${MLFLOW_AUTH_DB_URI}
admin_username = ${MLFLOW_AUTH_ADMIN_USERNAME}
admin_password = ${MLFLOW_AUTH_ADMIN_PASSWORD}
authorization_function = ${MLFLOW_AUTH_AUTHORIZATION_FUNCTION}
EOF

chmod 600 "${MLFLOW_AUTH_CONFIG_PATH}"
echo "Wrote auth config to ${MLFLOW_AUTH_CONFIG_PATH}"
