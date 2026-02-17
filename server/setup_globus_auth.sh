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

CONFIG_DIR="${GENERATED_DIR:-${MLFLOW_HOME:-${SCRIPT_DIR}/runtime}/generated}"
mkdir -p "${CONFIG_DIR}"

OAUTH_CFG="${CONFIG_DIR}/oauth2-proxy.cfg"
NGINX_CFG="${CONFIG_DIR}/nginx-mlflow-globus.conf"
ALLOWED_EMAILS_FILE="${CONFIG_DIR}/oauth2-proxy-allowed-emails.txt"
GENERATE_VM_NGINX_CONF="${GENERATE_VM_NGINX_CONF:-true}"
GENERATE_VM_NGINX_CONF="$(echo "${GENERATE_VM_NGINX_CONF}" | tr '[:upper:]' '[:lower:]')"

VM_NGINX_SERVER_NAME="${VM_NGINX_SERVER_NAME:-${PUBLIC_BASE_URL#https://}}"
VM_NGINX_SERVER_NAME="${VM_NGINX_SERVER_NAME#http://}"
VM_NGINX_SERVER_NAME="${VM_NGINX_SERVER_NAME%%/*}"
VM_TLS_CERT_PATH="${VM_TLS_CERT_PATH:-/etc/letsencrypt/live/${VM_NGINX_SERVER_NAME}/fullchain.pem}"
VM_TLS_KEY_PATH="${VM_TLS_KEY_PATH:-/etc/letsencrypt/live/${VM_NGINX_SERVER_NAME}/privkey.pem}"
OAUTH2_PROXY_UPSTREAM_SERVER="${OAUTH2_PROXY_HTTP_ADDRESS#http://}"
OAUTH2_PROXY_UPSTREAM_SERVER="${OAUTH2_PROXY_UPSTREAM_SERVER#https://}"

AUTH_EMAILS_CFG_LINE=""
if [[ -n "${OAUTH2_PROXY_ALLOWED_EMAILS:-}" ]]; then
  : > "${ALLOWED_EMAILS_FILE}"
  IFS=',' read -r -a raw_allowed_emails <<< "${OAUTH2_PROXY_ALLOWED_EMAILS}"
  valid_count=0
  for raw_email in "${raw_allowed_emails[@]}"; do
    email="$(printf '%s' "${raw_email}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    if [[ -z "${email}" ]]; then
      continue
    fi
    if [[ "${email}" != *@* ]]; then
      echo "Invalid email in OAUTH2_PROXY_ALLOWED_EMAILS: ${email}"
      exit 1
    fi
    printf '%s\n' "${email}" >> "${ALLOWED_EMAILS_FILE}"
    valid_count=$((valid_count + 1))
  done
  if [[ "${valid_count}" -eq 0 ]]; then
    echo "OAUTH2_PROXY_ALLOWED_EMAILS is set but no valid emails were found."
    exit 1
  fi
  chmod 600 "${ALLOWED_EMAILS_FILE}"
  AUTH_EMAILS_CFG_LINE="authenticated_emails_file = \"${ALLOWED_EMAILS_FILE}\""
fi

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
${AUTH_EMAILS_CFG_LINE}
cookie_secure = true
cookie_secret = "${OAUTH2_PROXY_COOKIE_SECRET}"
cookie_httponly = true
cookie_samesite = "lax"
set_xauthrequest = true
pass_user_headers = true
pass_authorization_header = false
set_authorization_header = false
pass_access_token = false
skip_provider_button = true
EOF

if [[ "${GENERATE_VM_NGINX_CONF}" == "true" ]]; then
cat > "${NGINX_CFG}" <<EOF
upstream mlflow_upstream {
    server 127.0.0.1:8080;
}

upstream oauth2_proxy {
    server ${OAUTH2_PROXY_UPSTREAM_SERVER};
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
        proxy_set_header X-User   \$user;
        proxy_set_header X-Email  \$email;
        # Prevent stale/basic Authorization headers from collapsing users
        # into one MLflow identity; bridge mode trusts X-Email instead.
        proxy_set_header Authorization "";

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
if [[ -n "${AUTH_EMAILS_CFG_LINE}" ]]; then
  echo "  ${ALLOWED_EMAILS_FILE}"
fi
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
