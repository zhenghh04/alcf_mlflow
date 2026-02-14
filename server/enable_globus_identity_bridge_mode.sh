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
    "MLFLOW_AUTH_AUTHORIZATION_FUNCTION": "auth_bridge:authenticate_request_globus_header",
    "MLFLOW_BRIDGE_USER_HEADER": "X-Email",
    "MLFLOW_BRIDGE_AUTO_CREATE_USERS": "true",
    "MLFLOW_BRIDGE_ALLOW_BASIC_FALLBACK_LOCAL_ONLY": "true",
    "MLFLOW_BRIDGE_TRUSTED_LOCAL_ADDRS": "127.0.0.1,::1,localhost",
    # Optional: comma-separated list for admin bootstrap via Globus identity.
    "MLFLOW_BRIDGE_ADMIN_EMAILS": "",
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

echo "Updated ${ENV_FILE} for Globus identity bridge mode."
echo
echo "Next:"
echo "  1) (Optional) set MLFLOW_BRIDGE_ADMIN_EMAILS=<comma-separated emails>"
echo "  2) bash ${SCRIPT_DIR}/setup_auth.sh"
echo "  3) bash ${SCRIPT_DIR}/setup_globus_auth.sh"
echo "  4) sudo systemctl restart mlflow-globus"
echo "  5) sudo systemctl restart oauth2-proxy"
echo
echo "Note: custom authorization_function may not support MLflow /gateway routes."
