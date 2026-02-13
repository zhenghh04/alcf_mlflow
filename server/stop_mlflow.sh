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

if [[ ! -f "${MLFLOW_PID_FILE}" ]]; then
  echo "No pid file found at ${MLFLOW_PID_FILE}. MLflow may not be running."
  exit 0
fi

pid="$(cat "${MLFLOW_PID_FILE}")"
if kill -0 "${pid}" 2>/dev/null; then
  kill "${pid}"
  sleep 1
  if kill -0 "${pid}" 2>/dev/null; then
    echo "Process ${pid} still running; sending SIGKILL"
    kill -9 "${pid}"
  fi
  echo "Stopped MLflow process ${pid}"
else
  echo "Process ${pid} is not running."
fi

rm -f "${MLFLOW_PID_FILE}"
