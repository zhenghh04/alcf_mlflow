#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <new_username> <new_password> [--admin]"
  exit 1
fi

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}."
  exit 1
fi

# shellcheck source=/dev/null
source "${ENV_FILE}"

NEW_USERNAME="$1"
NEW_PASSWORD="$2"
MAKE_ADMIN="${3:-}"

TRACKING_URI="${MLFLOW_TRACKING_URI:-http://127.0.0.1:${MLFLOW_PORT}}"
ADMIN_USERNAME="${MLFLOW_TRACKING_USERNAME:-${MLFLOW_AUTH_ADMIN_USERNAME}}"
ADMIN_PASSWORD="${MLFLOW_TRACKING_PASSWORD:-${MLFLOW_AUTH_ADMIN_PASSWORD}}"

export MLFLOW_TRACKING_URI="${TRACKING_URI}"
export MLFLOW_TRACKING_USERNAME="${ADMIN_USERNAME}"
export MLFLOW_TRACKING_PASSWORD="${ADMIN_PASSWORD}"

"${VENV_DIR}/bin/python" - <<'PY' "$NEW_USERNAME" "$NEW_PASSWORD" "$MAKE_ADMIN"
import os
import sys

import mlflow.server

username = sys.argv[1]
password = sys.argv[2]
make_admin = sys.argv[3] == "--admin"

tracking_uri = os.environ["MLFLOW_TRACKING_URI"]
client = mlflow.server.get_app_client("basic-auth", tracking_uri=tracking_uri)
client.create_user(username=username, password=password)
if make_admin:
    client.update_user_admin(username=username, is_admin=True)

print(f"Created user '{username}' on {tracking_uri} (admin={make_admin})")
PY
