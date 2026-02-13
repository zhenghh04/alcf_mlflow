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

mkdir -p "$(dirname "${MLFLOW_LOG_FILE}")" "$(dirname "${MLFLOW_PID_FILE}")" "${ARTIFACT_ROOT}" "${MLFLOW_HOME}/data"

# shellcheck source=/dev/null
source "${VENV_DIR}/bin/activate"

nohup mlflow server \
  --host "${MLFLOW_HOST}" \
  --port "${MLFLOW_PORT}" \
  --backend-store-uri "${BACKEND_STORE_URI}" \
  --default-artifact-root "${ARTIFACT_ROOT}" \
  > "${MLFLOW_LOG_FILE}" 2>&1 &

echo $! > "${MLFLOW_PID_FILE}"
echo "Started MLflow (PID $(cat "${MLFLOW_PID_FILE}"))"
echo "Log file: ${MLFLOW_LOG_FILE}"
echo "URL: http://${MLFLOW_HOST}:${MLFLOW_PORT}"
