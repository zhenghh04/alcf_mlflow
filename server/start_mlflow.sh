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

if [[ "${AUTH_ENABLED}" == "true" && "${GLOBUS_ENABLED}" == "true" ]]; then
  echo "Both ENABLE_MLFLOW_AUTH and ENABLE_GLOBUS_AUTH are true."
  echo "Set only one auth mode in server/.env."
  exit 1
fi

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

if lsof -ti tcp:"${MLFLOW_PORT}" >/dev/null 2>&1; then
  conflicting_pid="$(lsof -ti tcp:"${MLFLOW_PORT}" | head -n1)"
  echo "Port ${MLFLOW_PORT} is already in use by PID ${conflicting_pid}."
  ps -p "${conflicting_pid}" -o pid=,ppid=,command=
  echo "Stop the existing process or choose a different MLFLOW_PORT in server/.env."
  exit 1
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
