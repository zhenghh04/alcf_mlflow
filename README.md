# MLflow Setup on ALCF VM

This folder contains a complete, VM-oriented setup for running an MLflow tracking server on an ALCF VM.

## Current server setup @ ALCF

- Hostname: `amsc-mlflow.alcf.anl.gov`
- Public URL: `https://mlflow.alcf.anl.gov`
- URL mapping: `https://mlflow.alcf.anl.gov` -> `amsc-mlflow.alcf.anl.gov:8080`

## What is included

- `server/.env.example`: environment variables for paths, ports, and proxy settings
- `server/setup_venv.sh`: create Python virtual environment and install MLflow
- `server/setup_auth.sh`: generate `basic_auth.ini` from `.env`
- `server/setup_globus_auth.sh`: generate `oauth2-proxy` and `nginx` configs from `.env`
- `server/setup_external_nginx_conf.sh`: generate external nginx `mlflow.conf` from `.env`
- `server/install_external_nginx_conf.sh`: install generated external nginx config and reload nginx
- `server/install_oauth2_proxy.sh`: build and install `oauth2-proxy` from GitHub source tag
- `server/start_mlflow.sh`: start MLflow server in background with log + pid files
- `server/stop_mlflow.sh`: stop the background MLflow server
- `server/health_check.sh`: validate server health endpoint
- `server/create_user.sh`: create users in MLflow basic-auth
- `server/mlflow.service`: optional systemd unit template
- `server/mlflow-globus.service`: systemd unit template for MLflow behind Globus proxy
- `server/oauth2-proxy.service`: systemd unit template for oauth2-proxy
- `server/install_systemd_globus.sh`: install + start Globus-mode systemd units
- `examples/log_example.py`: minimal experiment logging test
- `client/configure_client.sh`: helper to export tracking URI and credentials

## Operations docs

- Runbook/checklist: `docs/operations-checklist.md`
- Architecture notes: `docs/mlflow-globus-architecture.md`
- Architecture diagram (SVG): `docs/mlflow-globus-architecture.svg`

## Quick start (user process mode)

```bash
cd mlflow
cp server/.env.example server/.env
# Edit server/.env for your VM paths and hostnames
# Set strong values for:
# - MLFLOW_FLASK_SERVER_SECRET_KEY
# - MLFLOW_AUTH_ADMIN_PASSWORD

bash server/setup_venv.sh
bash server/setup_auth.sh
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
export MLFLOW_TRACKING_USERNAME=admin
export MLFLOW_TRACKING_PASSWORD='<admin-password>'
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
- MLflow security middleware: for non-local access, set both
  - `MLFLOW_ALLOWED_HOSTS` (includes `mlflow.alcf.anl.gov` and `amsc-mlflow.alcf.anl.gov`)
  - `MLFLOW_CORS_ALLOWED_ORIGINS` (includes `https://mlflow.alcf.anl.gov`)
- MLflow auth app requires:
  - `MLFLOW_FLASK_SERVER_SECRET_KEY` (static secret key in `.env`)
  - `MLFLOW_AUTH_CONFIG_PATH` pointing to your generated `basic_auth.ini`

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

## Authentication setup

This setup enables MLflow built-in basic authentication (`--app-name basic-auth`).

1. Configure auth values in `server/.env`:
   - `ENABLE_MLFLOW_AUTH=true`
   - `MLFLOW_FLASK_SERVER_SECRET_KEY=<long random secret>`
   - `MLFLOW_AUTH_ADMIN_USERNAME=admin`
   - `MLFLOW_AUTH_ADMIN_PASSWORD=<strong password>`
2. Generate auth config:
   ```bash
   bash server/setup_auth.sh
   ```
3. Start server:
   ```bash
   bash server/start_mlflow.sh
   ```
4. Create additional users:
   ```bash
   bash server/create_user.sh alice 'strong-password'
   bash server/create_user.sh bob 'another-strong-password' --admin
   ```
5. Configure client auth when tracking:
   ```bash
   source server/venv/bin/activate
   bash client/configure_client.sh https://mlflow.alcf.anl.gov alice 'strong-password'
   ```

## Globus Auth setup (recommended for `mlflow.alcf.anl.gov`)

Use Globus OIDC in front of MLflow with `oauth2-proxy` + `nginx`.

1. In `server/.env`, set:
   - `ENABLE_GLOBUS_AUTH=true`
   - `ENABLE_MLFLOW_AUTH=false`
   - `GLOBUS_OAUTH_CLIENT_ID=<client-id>`
   - `GLOBUS_OAUTH_CLIENT_SECRET=<client-secret>`
   - `OAUTH2_PROXY_COOKIE_SECRET=<32-byte-base64-secret>`
   - If TLS/auth routing is handled by external nginx (outside VM), set `GENERATE_VM_NGINX_CONF=false`
2. Keep MLflow internal-only behind proxy (recommended):
   - `MLFLOW_HOST=127.0.0.1`
3. Generate proxy configs:
   ```bash
   bash server/setup_globus_auth.sh
   ```
4. Install generated files:
   - `server/generated/oauth2-proxy.cfg` -> your oauth2-proxy runtime config path
   - `server/generated/nginx-mlflow-globus.conf` -> your nginx site config path (only when `GENERATE_VM_NGINX_CONF=true`)
5. Install `oauth2-proxy` binary:
   ```bash
   bash server/install_oauth2_proxy.sh
   ```
6. Install and start systemd units:
   ```bash
   bash server/install_systemd_globus.sh
   ```
7. If VM nginx is used (`GENERATE_VM_NGINX_CONF=true`), install nginx config and reload nginx:
   ```bash
   sudo cp server/generated/nginx-mlflow-globus.conf /etc/nginx/conf.d/mlflow-globus.conf
   sudo nginx -t
   sudo systemctl reload nginx
   ```
8. If external nginx is used (`GENERATE_VM_NGINX_CONF=false`), configure external nginx to:
   - route `/oauth2/auth` and `/oauth2/` to VM `oauth2-proxy` (`OAUTH2_PROXY_HTTP_ADDRESS`)
   - use `auth_request /oauth2/auth;` on `/`, then proxy authenticated traffic to MLflow (`MLFLOW_INTERNAL_UPSTREAM` on VM)
   - or generate/install an external nginx config from this repo:
   ```bash
   bash server/setup_external_nginx_conf.sh
   bash server/install_external_nginx_conf.sh
   ```

## Stop server

```bash
bash server/stop_mlflow.sh
```

## Troubleshooting

- `NumPy/SciPy` mismatch errors (for example `A NumPy version >=1.21.6 and <1.28.0 is required`):
  - Cause: running MLflow from a different Python environment (often base Conda), not `server/venv`.
  - Fix:
    ```bash
    bash server/setup_venv.sh
    bash server/start_mlflow.sh
    ```
  - The setup script pins compatible versions (`numpy<2`, `scipy<1.12`).

- `ERROR: [Errno 48] Address already in use`:
  - Cause: another process is already listening on your configured port (default `8080`).
  - Fix:
    ```bash
    lsof -nP -iTCP:8080 -sTCP:LISTEN
    ```
    Stop the existing process, or change `MLFLOW_PORT` in `server/.env`.
