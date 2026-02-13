#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
EXAMPLE_ENV_FILE="${SCRIPT_DIR}/.env.example"

if [[ ! -f "${ENV_FILE}" ]]; then
  cp "${EXAMPLE_ENV_FILE}" "${ENV_FILE}"
  echo "Created ${ENV_FILE} from template. Review values before starting MLflow."
fi

# shellcheck source=/dev/null
source "${ENV_FILE}"

mkdir -p "${MLFLOW_HOME}/data" "${ARTIFACT_ROOT}" "${MLFLOW_HOME}/logs" "${MLFLOW_HOME}/run"

python3 -m venv "${VENV_DIR}"
# shellcheck source=/dev/null
source "${VENV_DIR}/bin/activate"

python -m pip install --upgrade pip
# Keep NumPy/SciPy ABI-compatible to avoid runtime import failures.
python -m pip install "numpy<2" "scipy<1.12" "mlflow[auth]"

echo "MLflow virtual environment ready at ${VENV_DIR}"
echo "Installed version: $(python -m pip show mlflow | awk '/Version:/{print $2}')"
