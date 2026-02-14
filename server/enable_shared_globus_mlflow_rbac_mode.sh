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
    "ENABLE_GLOBUS_AUTH": "true",
    "MLFLOW_USER_ADMIN_TRACKING_URI": "http://127.0.0.1:8080",
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
echo "  ENABLE_GLOBUS_AUTH=true"
echo "  MLFLOW_USER_ADMIN_TRACKING_URI=http://127.0.0.1:8080"
echo
echo "Next:"
echo "  1) bash ${SCRIPT_DIR}/setup_auth.sh"
echo "  2) bash ${SCRIPT_DIR}/setup_globus_auth.sh"
echo "  3) sudo systemctl restart mlflow-globus"
echo "  4) sudo systemctl restart oauth2-proxy"
echo "  5) Manage users via ${SCRIPT_DIR}/create_user.sh"

