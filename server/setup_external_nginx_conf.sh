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

if [[ "${ENABLE_GLOBUS_AUTH:-false}" != "true" ]]; then
  echo "ENABLE_GLOBUS_AUTH must be true in server/.env for external oauth2-proxy auth."
  exit 1
fi

for var_name in PUBLIC_BASE_URL OAUTH2_PROXY_HTTP_ADDRESS MLFLOW_PORT; do
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

OAUTH2_PROXY_ENDPOINT="${OAUTH2_PROXY_HTTP_ADDRESS#http://}"
OAUTH2_PROXY_ENDPOINT="${OAUTH2_PROXY_ENDPOINT#https://}"
OAUTH2_PROXY_PORT="${OAUTH2_PROXY_ENDPOINT##*:}"

if [[ ! "${OAUTH2_PROXY_PORT}" =~ ^[0-9]+$ ]]; then
  echo "Could not parse oauth2-proxy port from OAUTH2_PROXY_HTTP_ADDRESS=${OAUTH2_PROXY_HTTP_ADDRESS}"
  exit 1
fi

OAUTH2_PROXY_UPSTREAM="${EXTERNAL_NGINX_OAUTH2_UPSTREAM:-${EXTERNAL_NGINX_UPSTREAM_HOST}:${OAUTH2_PROXY_PORT}}"
MLFLOW_UPSTREAM="${EXTERNAL_NGINX_MLFLOW_UPSTREAM:-${EXTERNAL_NGINX_UPSTREAM_HOST}:${MLFLOW_PORT}}"

TLS_CERT_PATH="${EXTERNAL_NGINX_TLS_CERT_PATH:-/etc/letsencrypt/live/${EXTERNAL_NGINX_SERVER_NAME}/fullchain.pem}"
TLS_KEY_PATH="${EXTERNAL_NGINX_TLS_KEY_PATH:-/etc/letsencrypt/live/${EXTERNAL_NGINX_SERVER_NAME}/privkey.pem}"
EXTERNAL_NGINX_USE_TLS="${EXTERNAL_NGINX_USE_TLS:-true}"
EXTERNAL_NGINX_USE_TLS="$(echo "${EXTERNAL_NGINX_USE_TLS}" | tr '[:upper:]' '[:lower:]')"

if [[ "${EXTERNAL_NGINX_USE_TLS}" != "true" && "${EXTERNAL_NGINX_USE_TLS}" != "false" ]]; then
  echo "EXTERNAL_NGINX_USE_TLS must be true or false."
  exit 1
fi

CONFIG_DIR="${SCRIPT_DIR}/generated"
mkdir -p "${CONFIG_DIR}"
OUTPUT_FILE="${CONFIG_DIR}/mlflow.conf"

if [[ "${EXTERNAL_NGINX_USE_TLS}" == "true" ]]; then
cat > "${OUTPUT_FILE}" <<EOF
upstream mlflow_vm {
    server ${MLFLOW_UPSTREAM};
}

upstream oauth2_proxy_vm {
    server ${OAUTH2_PROXY_UPSTREAM};
}

server {
    listen 443 ssl http2;
    server_name ${EXTERNAL_NGINX_SERVER_NAME};

    ssl_certificate ${TLS_CERT_PATH};
    ssl_certificate_key ${TLS_KEY_PATH};

    # oauth2-proxy callback can set large cookies; raise upstream header buffers.
    proxy_buffer_size 32k;
    proxy_buffers 8 32k;
    proxy_busy_buffers_size 64k;

    location = /oauth2/auth {
        proxy_pass http://oauth2_proxy_vm;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Auth-Request-Redirect \$request_uri;
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
    }

    location /oauth2/ {
        proxy_pass http://oauth2_proxy_vm;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Scheme \$scheme;
    }

    location / {
        auth_request /oauth2/auth;
        error_page 401 = /oauth2/sign_in;

        auth_request_set \$user  \$upstream_http_x_auth_request_user;
        auth_request_set \$email \$upstream_http_x_auth_request_email;
        auth_request_set \$authz \$upstream_http_authorization;
        proxy_set_header X-User \$user;
        proxy_set_header X-Email \$email;
        proxy_set_header Authorization \$authz;

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

upstream oauth2_proxy_vm {
    server ${OAUTH2_PROXY_UPSTREAM};
}

server {
    listen 80;
    server_name ${EXTERNAL_NGINX_SERVER_NAME};

    # oauth2-proxy callback can set large cookies; raise upstream header buffers.
    proxy_buffer_size 32k;
    proxy_buffers 8 32k;
    proxy_busy_buffers_size 64k;

    location = /oauth2/auth {
        proxy_pass http://oauth2_proxy_vm;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Auth-Request-Redirect \$request_uri;
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
    }

    location /oauth2/ {
        proxy_pass http://oauth2_proxy_vm;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Scheme https;
    }

    location / {
        auth_request /oauth2/auth;
        error_page 401 = /oauth2/sign_in;

        auth_request_set \$user  \$upstream_http_x_auth_request_user;
        auth_request_set \$email \$upstream_http_x_auth_request_email;
        auth_request_set \$authz \$upstream_http_authorization;
        proxy_set_header X-User \$user;
        proxy_set_header X-Email \$email;
        proxy_set_header Authorization \$authz;

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

echo "Generated:"
echo "  ${OUTPUT_FILE}"
echo
echo "Resolved values:"
echo "  EXTERNAL_NGINX_SERVER_NAME=${EXTERNAL_NGINX_SERVER_NAME}"
echo "  EXTERNAL_NGINX_USE_TLS=${EXTERNAL_NGINX_USE_TLS}"
echo "  EXTERNAL_NGINX_MLFLOW_UPSTREAM=${MLFLOW_UPSTREAM}"
echo "  EXTERNAL_NGINX_OAUTH2_UPSTREAM=${OAUTH2_PROXY_UPSTREAM}"
