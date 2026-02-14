#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}. Run setup_venv.sh first."
  exit 1
fi

# shellcheck source=/dev/null
source "${ENV_FILE}"

if [[ -f "${MLFLOW_PID_FILE}" ]]; then
  existing_pid="$(cat "${MLFLOW_PID_FILE}")"
  if kill -0 "${existing_pid}" 2>/dev/null; then
    echo "MLflow is already running with PID ${existing_pid}"
    exit 0
  else
    rm -f "${MLFLOW_PID_FILE}"
  fi
fi

if [[ ! -x "${VENV_DIR}/bin/mlflow" ]]; then
  echo "MLflow is not installed in ${VENV_DIR}. Run setup_venv.sh first."
  exit 1
fi

AUTH_ENABLED="${ENABLE_MLFLOW_AUTH:-true}"
AUTH_ENABLED="$(echo "${AUTH_ENABLED}" | tr '[:upper:]' '[:lower:]')"
GLOBUS_ENABLED="${ENABLE_GLOBUS_AUTH:-false}"
GLOBUS_ENABLED="$(echo "${GLOBUS_ENABLED}" | tr '[:upper:]' '[:lower:]')"

if [[ "${AUTH_ENABLED}" == "true" ]]; then
  if [[ -z "${MLFLOW_FLASK_SERVER_SECRET_KEY:-}" || "${MLFLOW_FLASK_SERVER_SECRET_KEY}" == "CHANGE_ME_WITH_LONG_RANDOM_SECRET" ]]; then
    echo "MLFLOW_FLASK_SERVER_SECRET_KEY is not set to a secure value in server/.env."
    exit 1
  fi

  if [[ -z "${MLFLOW_AUTH_ADMIN_PASSWORD:-}" || "${MLFLOW_AUTH_ADMIN_PASSWORD}" == "CHANGE_ME_WITH_STRONG_PASSWORD" ]]; then
    echo "MLFLOW_AUTH_ADMIN_PASSWORD is not set to a secure value in server/.env."
    exit 1
  fi

  if [[ ! -f "${MLFLOW_AUTH_CONFIG_PATH}" ]]; then
    "${SCRIPT_DIR}/setup_auth.sh"
  fi

  export MLFLOW_FLASK_SERVER_SECRET_KEY
  export MLFLOW_AUTH_CONFIG_PATH
fi

# MLflow server reads this only from environment variables.
if [[ -n "${MLFLOW_SERVER_ENABLE_JOB_EXECUTION:-}" ]]; then
  export MLFLOW_SERVER_ENABLE_JOB_EXECUTION
fi

mapfile -t conflicting_pids < <(lsof -t -iTCP:"${MLFLOW_PORT}" -sTCP:LISTEN 2>/dev/null | awk '!seen[$0]++')
if [[ "${#conflicting_pids[@]}" -gt 0 ]]; then
  echo "Port ${MLFLOW_PORT} has ${#conflicting_pids[@]} listening process(es):"
  for pid in "${conflicting_pids[@]}"; do
    ps -p "${pid}" -o pid=,ppid=,command= || true
  done
  echo "Stopping existing listener(s) on port ${MLFLOW_PORT}..."
  for pid in "${conflicting_pids[@]}"; do
    kill "${pid}" 2>/dev/null || true
  done

  # Wait briefly for graceful shutdown, then force kill if still listening.
  sleep 1
  mapfile -t remaining_conflicting_pids < <(lsof -t -iTCP:"${MLFLOW_PORT}" -sTCP:LISTEN 2>/dev/null | awk '!seen[$0]++')
  if [[ "${#remaining_conflicting_pids[@]}" -gt 0 ]]; then
    echo "Force-stopping remaining listener(s) on port ${MLFLOW_PORT}..."
    for pid in "${remaining_conflicting_pids[@]}"; do
      kill -9 "${pid}" 2>/dev/null || true
    done
  fi
fi

mkdir -p "$(dirname "${MLFLOW_LOG_FILE}")" "$(dirname "${MLFLOW_PID_FILE}")" "${ARTIFACT_ROOT}" "${MLFLOW_HOME}/data"

cmd=(
  "${VENV_DIR}/bin/mlflow" server
  --host "${MLFLOW_HOST}"
  --port "${MLFLOW_PORT}"
  --allowed-hosts "${MLFLOW_ALLOWED_HOSTS}"
  --cors-allowed-origins "${MLFLOW_CORS_ALLOWED_ORIGINS}"
  --backend-store-uri "${BACKEND_STORE_URI}"
  --default-artifact-root "${ARTIFACT_ROOT}"
)

if [[ "${AUTH_ENABLED}" == "true" ]]; then
  cmd+=(--app-name basic-auth)
fi

nohup "${cmd[@]}" > "${MLFLOW_LOG_FILE}" 2>&1 &

echo $! > "${MLFLOW_PID_FILE}"
echo "Started MLflow (PID $(cat "${MLFLOW_PID_FILE}"))"
echo "Log file: ${MLFLOW_LOG_FILE}"
echo "URL: http://${MLFLOW_HOST}:${MLFLOW_PORT}"
