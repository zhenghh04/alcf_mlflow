#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}."
  exit 1
fi

# shellcheck source=/dev/null
source "${ENV_FILE}"

for var_name in PUBLIC_BASE_URL MLFLOW_PORT; do
  if [[ -z "${!var_name:-}" ]]; then
    echo "Missing ${var_name} in server/.env."
    exit 1
  fi
done

PUBLIC_HOST="${PUBLIC_BASE_URL#https://}"
PUBLIC_HOST="${PUBLIC_HOST#http://}"
PUBLIC_HOST="${PUBLIC_HOST%%/*}"

EXTERNAL_NGINX_SERVER_NAME="${EXTERNAL_NGINX_SERVER_NAME:-${PUBLIC_HOST}}"
DEFAULT_UPSTREAM_HOST="$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo "127.0.0.1")"
EXTERNAL_NGINX_UPSTREAM_HOST="${EXTERNAL_NGINX_UPSTREAM_HOST:-${DEFAULT_UPSTREAM_HOST}}"
MLFLOW_UPSTREAM="${EXTERNAL_NGINX_MLFLOW_UPSTREAM:-${EXTERNAL_NGINX_UPSTREAM_HOST}:${MLFLOW_PORT}}"

EXTERNAL_NGINX_USE_TLS="${EXTERNAL_NGINX_USE_TLS:-true}"
EXTERNAL_NGINX_USE_TLS="$(echo "${EXTERNAL_NGINX_USE_TLS}" | tr '[:upper:]' '[:lower:]')"
if [[ "${EXTERNAL_NGINX_USE_TLS}" != "true" && "${EXTERNAL_NGINX_USE_TLS}" != "false" ]]; then
  echo "EXTERNAL_NGINX_USE_TLS must be true or false."
  exit 1
fi

TLS_CERT_PATH="${EXTERNAL_NGINX_TLS_CERT_PATH:-/etc/letsencrypt/live/${EXTERNAL_NGINX_SERVER_NAME}/fullchain.pem}"
TLS_KEY_PATH="${EXTERNAL_NGINX_TLS_KEY_PATH:-/etc/letsencrypt/live/${EXTERNAL_NGINX_SERVER_NAME}/privkey.pem}"

CONFIG_DIR="${GENERATED_DIR:-${MLFLOW_HOME:-${SCRIPT_DIR}/runtime}/generated}"
mkdir -p "${CONFIG_DIR}"
OUTPUT_FILE="${CONFIG_DIR}/mlflow-basic-auth.conf"

if [[ "${EXTERNAL_NGINX_USE_TLS}" == "true" ]]; then
cat > "${OUTPUT_FILE}" <<EOF
upstream mlflow_vm {
    server ${MLFLOW_UPSTREAM};
}

server {
    listen 443 ssl http2;
    server_name ${EXTERNAL_NGINX_SERVER_NAME};

    ssl_certificate ${TLS_CERT_PATH};
    ssl_certificate_key ${TLS_KEY_PATH};

    location / {
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_pass http://mlflow_vm;
    }
}
EOF
else
cat > "${OUTPUT_FILE}" <<EOF
upstream mlflow_vm {
    server ${MLFLOW_UPSTREAM};
}

server {
    listen 80;
    server_name ${EXTERNAL_NGINX_SERVER_NAME};

    location / {
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_http_version 1.1;
        proxy_pass http://mlflow_vm;
    }
}
EOF
fi

chmod 600 "${OUTPUT_FILE}"
echo "Generated: ${OUTPUT_FILE}"
echo "Mode: MLflow built-in auth/RBAC (no oauth2-proxy auth_request)"
echo "Upstream: ${MLFLOW_UPSTREAM}"
