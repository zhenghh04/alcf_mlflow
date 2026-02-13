#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <mlflow_server_uri> [username] [password]"
  echo "Example: $0 https://mlflow.alcf.anl.gov alice strong-password"
  exit 1
fi

export MLFLOW_TRACKING_URI="$1"
echo "MLFLOW_TRACKING_URI=${MLFLOW_TRACKING_URI}"

if [[ $# -ge 3 ]]; then
  export MLFLOW_TRACKING_USERNAME="$2"
  export MLFLOW_TRACKING_PASSWORD="$3"
  echo "MLFLOW_TRACKING_USERNAME=${MLFLOW_TRACKING_USERNAME}"
  echo "MLFLOW_TRACKING_PASSWORD is set"
fi

echo "Add this export to your shell profile if you want it persistent."
