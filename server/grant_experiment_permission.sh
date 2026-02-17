#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <username> <experiment_id> <READ|EDIT|MANAGE>"
  exit 1
fi

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}."
  exit 1
fi

# shellcheck source=/dev/null
source "${ENV_FILE}"

USERNAME="$1"
EXPERIMENT_ID="$2"
PERMISSION="$(echo "$3" | tr '[:lower:]' '[:upper:]')"

case "${PERMISSION}" in
  READ|EDIT|MANAGE) ;;
  *)
    echo "Invalid permission: ${PERMISSION}"
    echo "Allowed: READ, EDIT, MANAGE"
    exit 1
    ;;
esac

TRACKING_URI="${MLFLOW_USER_ADMIN_TRACKING_URI:-http://127.0.0.1:${MLFLOW_PORT}}"
ADMIN_USERNAME="${MLFLOW_TRACKING_USERNAME:-${MLFLOW_AUTH_ADMIN_USERNAME}}"
ADMIN_PASSWORD="${MLFLOW_TRACKING_PASSWORD:-${MLFLOW_AUTH_ADMIN_PASSWORD}}"

export MLFLOW_TRACKING_URI="${TRACKING_URI}"
export MLFLOW_TRACKING_USERNAME="${ADMIN_USERNAME}"
export MLFLOW_TRACKING_PASSWORD="${ADMIN_PASSWORD}"

"${VENV_DIR}/bin/python" - <<'PY' "$USERNAME" "$EXPERIMENT_ID" "$PERMISSION"
import os
import sys

import mlflow.server
from mlflow.exceptions import MlflowException

username = sys.argv[1]
experiment_id = sys.argv[2]
permission = sys.argv[3]
tracking_uri = os.environ["MLFLOW_TRACKING_URI"]

client = mlflow.server.get_app_client("basic-auth", tracking_uri=tracking_uri)
try:
    client.create_experiment_permission(
        experiment_id=experiment_id,
        username=username,
        permission=permission,
    )
except MlflowException as e:
    # If permission already exists, update it instead.
    if "already exists" in str(e).lower():
        client.update_experiment_permission(
            experiment_id=experiment_id,
            username=username,
            permission=permission,
        )
    else:
        raise

print(
    f"Granted {permission} on experiment {experiment_id} to {username} "
    f"via {tracking_uri}"
)
PY

