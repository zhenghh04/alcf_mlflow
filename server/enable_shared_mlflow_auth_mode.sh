#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}."
  exit 1
fi

python3 - <<'PY' "${ENV_FILE}"
import sys
from pathlib import Path

env_path = Path(sys.argv[1])
lines = env_path.read_text().splitlines()

updates = {
    "ENABLE_MLFLOW_AUTH": "true",
    "ENABLE_GLOBUS_AUTH": "false",
}

seen = set()
out = []
for line in lines:
    if "=" in line and not line.lstrip().startswith("#"):
        key = line.split("=", 1)[0]
        if key in updates:
            out.append(f"{key}={updates[key]}")
            seen.add(key)
            continue
    out.append(line)

for key, value in updates.items():
    if key not in seen:
        out.append(f"{key}={value}")

env_path.write_text("\n".join(out) + "\n")
PY

echo "Updated ${ENV_FILE}:"
echo "  ENABLE_MLFLOW_AUTH=true"
echo "  ENABLE_GLOBUS_AUTH=false"
echo
echo "Next:"
echo "  1) bash ${SCRIPT_DIR}/setup_auth.sh"
echo "  2) sudo systemctl restart mlflow-globus   (or restart your mlflow service/process)"
echo "  3) Update external nginx to proxy directly to MLflow (no /oauth2 auth_request)"
echo "  4) Create users via: bash ${SCRIPT_DIR}/create_user.sh <username> <password> [--admin]"

