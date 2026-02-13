#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <mlflow_server_uri>"
  echo "Example: $0 http://amsc-mlflow.alcf.anl.gov:5000"
  exit 1
fi

export MLFLOW_TRACKING_URI="$1"
echo "MLFLOW_TRACKING_URI=${MLFLOW_TRACKING_URI}"
echo "Add this export to your shell profile if you want it persistent."
