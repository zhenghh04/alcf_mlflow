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

if [[ "${ENABLE_GLOBUS_AUTH:-false}" != "true" ]]; then
  echo "ENABLE_GLOBUS_AUTH is not true in server/.env."
  echo "Set ENABLE_GLOBUS_AUTH=true, then rerun."
  exit 1
fi

if [[ "${ENABLE_MLFLOW_AUTH:-false}" == "true" ]]; then
  echo "ENABLE_MLFLOW_AUTH=true and ENABLE_GLOBUS_AUTH=true are mutually exclusive."
  echo "Set ENABLE_MLFLOW_AUTH=false for Globus SSO mode."
  exit 1
fi

for var_name in \
  PUBLIC_BASE_URL \
  MLFLOW_INTERNAL_UPSTREAM \
  GLOBUS_OIDC_ISSUER_URL \
  GLOBUS_OAUTH_CLIENT_ID \
  GLOBUS_OAUTH_CLIENT_SECRET \
  OAUTH2_PROXY_COOKIE_SECRET; do
  if [[ -z "${!var_name:-}" ]]; then
    echo "Missing ${var_name} in server/.env."
    exit 1
  fi
done

if [[ "${GLOBUS_OAUTH_CLIENT_ID}" == "REPLACE_WITH_GLOBUS_CLIENT_ID" ]]; then
  echo "Set real Globus client credentials before generating configs."
  exit 1
fi

if [[ "${GLOBUS_OAUTH_CLIENT_SECRET}" == "REPLACE_WITH_GLOBUS_CLIENT_SECRET" ]]; then
  echo "Set real Globus client credentials before generating configs."
  exit 1
fi

CONFIG_DIR="${SCRIPT_DIR}/generated"
mkdir -p "${CONFIG_DIR}"

OAUTH_CFG="${CONFIG_DIR}/oauth2-proxy.cfg"
NGINX_CFG="${CONFIG_DIR}/nginx-mlflow-globus.conf"
GENERATE_VM_NGINX_CONF="${GENERATE_VM_NGINX_CONF:-true}"
GENERATE_VM_NGINX_CONF="$(echo "${GENERATE_VM_NGINX_CONF}" | tr '[:upper:]' '[:lower:]')"

VM_NGINX_SERVER_NAME="${VM_NGINX_SERVER_NAME:-${PUBLIC_BASE_URL#https://}}"
VM_NGINX_SERVER_NAME="${VM_NGINX_SERVER_NAME#http://}"
VM_NGINX_SERVER_NAME="${VM_NGINX_SERVER_NAME%%/*}"
VM_TLS_CERT_PATH="${VM_TLS_CERT_PATH:-/etc/letsencrypt/live/${VM_NGINX_SERVER_NAME}/fullchain.pem}"
VM_TLS_KEY_PATH="${VM_TLS_KEY_PATH:-/etc/letsencrypt/live/${VM_NGINX_SERVER_NAME}/privkey.pem}"

cat > "${OAUTH_CFG}" <<EOF
provider = "oidc"
oidc_issuer_url = "${GLOBUS_OIDC_ISSUER_URL}"
client_id = "${GLOBUS_OAUTH_CLIENT_ID}"
client_secret = "${GLOBUS_OAUTH_CLIENT_SECRET}"
redirect_url = "${PUBLIC_BASE_URL}/oauth2/callback"
upstreams = [ "${MLFLOW_INTERNAL_UPSTREAM}" ]
http_address = "${OAUTH2_PROXY_HTTP_ADDRESS}"
scope = "openid profile email"
email_domains = [ "${OAUTH2_PROXY_EMAIL_DOMAINS}" ]
cookie_secure = true
cookie_secret = "${OAUTH2_PROXY_COOKIE_SECRET}"
cookie_httponly = true
cookie_samesite = "lax"
set_xauthrequest = true
pass_authorization_header = true
set_authorization_header = true
pass_access_token = true
skip_provider_button = true
EOF

if [[ "${GENERATE_VM_NGINX_CONF}" == "true" ]]; then
cat > "${NGINX_CFG}" <<EOF
upstream mlflow_upstream {
    server 127.0.0.1:8080;
}

upstream oauth2_proxy {
    server 127.0.0.1:4180;
}

server {
    listen 443 ssl http2;
    server_name ${VM_NGINX_SERVER_NAME};

    # Replace with your certificate paths.
    ssl_certificate ${VM_TLS_CERT_PATH};
    ssl_certificate_key ${VM_TLS_KEY_PATH};

    location = /oauth2/auth {
        proxy_pass http://oauth2_proxy;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Auth-Request-Redirect \$request_uri;
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
    }

    location /oauth2/ {
        proxy_pass http://oauth2_proxy;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Scheme \$scheme;
    }

    location / {
        auth_request /oauth2/auth;
        error_page 401 = /oauth2/sign_in;

        auth_request_set \$user   \$upstream_http_x_auth_request_user;
        auth_request_set \$email  \$upstream_http_x_auth_request_email;
        auth_request_set \$authz  \$upstream_http_authorization;
        proxy_set_header X-User   \$user;
        proxy_set_header X-Email  \$email;
        proxy_set_header Authorization \$authz;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_pass http://mlflow_upstream;
    }
}
EOF
fi

chmod 600 "${OAUTH_CFG}"
if [[ "${GENERATE_VM_NGINX_CONF}" == "true" ]]; then
  chmod 600 "${NGINX_CFG}"
fi

echo "Generated:"
echo "  ${OAUTH_CFG}"
if [[ "${GENERATE_VM_NGINX_CONF}" == "true" ]]; then
  echo "  ${NGINX_CFG}"
fi
echo
echo "Next:"
echo "  1) Install oauth2-proxy and run with ${OAUTH_CFG}"
if [[ "${GENERATE_VM_NGINX_CONF}" == "true" ]]; then
  echo "  2) Install nginx conf from ${NGINX_CFG}"
  echo "  3) Keep MLflow running at ${MLFLOW_INTERNAL_UPSTREAM}"
else
  echo "  2) Configure your external nginx to use oauth2-proxy at ${OAUTH2_PROXY_HTTP_ADDRESS}"
  echo "  3) Keep MLflow running at ${MLFLOW_INTERNAL_UPSTREAM}"
fi
