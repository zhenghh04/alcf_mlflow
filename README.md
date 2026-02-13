# MLflow Setup on ALCF VM

This folder contains a complete, VM-oriented setup for running an MLflow tracking server on an ALCF VM.

## Current server setup

- Hostname: `amsc-mlflow.alcf.anl.gov`
- Public URL: `https://mlflow.alcf.anl.gov`
- URL mapping: `https://mlflow.alcf.anl.gov` -> `amsc-mlflow.alcf.anl.gov:8080`

## What is included

- `server/.env.example`: environment variables for paths, ports, and proxy settings
- `server/setup_venv.sh`: create Python virtual environment and install MLflow
- `server/start_mlflow.sh`: start MLflow server in background with log + pid files
- `server/stop_mlflow.sh`: stop the background MLflow server
- `server/health_check.sh`: validate server health endpoint
- `server/mlflow.service`: optional systemd unit template
- `examples/log_example.py`: minimal experiment logging test
- `client/configure_client.sh`: helper to export `MLFLOW_TRACKING_URI`

## Quick start (user process mode)

```bash
cd mlflow
cp server/.env.example server/.env
# Edit server/.env for your VM paths and hostnames

bash server/setup_venv.sh
bash server/start_mlflow.sh
bash server/health_check.sh
```

Expected health response:

```text
{"status": "OK"}
```

Run a logging test:

```bash
source server/venv/bin/activate
python examples/log_example.py
```

Then open in browser:

```text
https://mlflow.alcf.anl.gov
```

## ALCF-specific notes

- If your VM requires outbound proxy, keep the default proxy lines in `server/.env`:
  - `http_proxy=http://proxy.alcf.anl.gov:3128`
  - `https_proxy=http://proxy.alcf.anl.gov:3128`
- If your VM does not need a proxy, comment those lines.
- Ensure your VM firewall/security group allows inbound TCP on `MLFLOW_PORT` (default `8080`).

## Optional: run with systemd

1. Update paths in `server/mlflow.service`.
2. Install service (requires sudo):

```bash
sudo cp server/mlflow.service /etc/systemd/system/mlflow.service
sudo systemctl daemon-reload
sudo systemctl enable --now mlflow
sudo systemctl status mlflow
```

## Backend and artifact storage

Default values in `.env.example`:

- Backend store: `sqlite:///<home>/mlflow/server/data/mlflow.db`
- Artifact root: `<home>/mlflow/server/artifacts`

For production, switch to PostgreSQL/MySQL for backend store and object storage (S3/MinIO) for artifacts.

## Stop server

```bash
bash server/stop_mlflow.sh
```
