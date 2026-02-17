# MLflow Globus Ops Checklist

## 1) Prerequisites

- External nginx is the public entrypoint for `https://mlflow.alcf.anl.gov`.
- VM services:
  - `oauth2-proxy` on `:8081`
  - `mlflow` on `:8080`
- Globus app redirect URI includes:
  - `https://mlflow.alcf.anl.gov/oauth2/callback`

## 2) Config Source of Truth

- Main env file: `server/.env`
- Generate oauth2-proxy config:
  - `bash server/setup_globus_auth.sh`
- Generate external nginx config:
  - `bash server/setup_external_nginx_conf.sh`

## 3) Apply Changes

### VM (oauth2-proxy / mlflow)

```bash
bash server/setup_globus_auth.sh
sudo systemctl restart oauth2-proxy
sudo systemctl restart mlflow-globus
```

### External nginx host

```bash
bash server/setup_external_nginx_conf.sh
bash server/install_external_nginx_conf.sh
```

## 4) Health Checks

### VM endpoint checks

```bash
curl -I http://amsc-mlflow.alcf.anl.gov:8081/oauth2/start
curl -I http://amsc-mlflow.alcf.anl.gov:8081/oauth2/auth
curl -I http://amsc-mlflow.alcf.anl.gov:8080/
```

Expected:
- `/oauth2/start` -> `302` (to `auth.globus.org`)
- `/oauth2/auth` -> `401` when unauthenticated
- `:8080 /` may be `403` direct access (acceptable)

### Public checks

```bash
curl -k -I https://mlflow.alcf.anl.gov/oauth2/start
curl -k -I "https://mlflow.alcf.anl.gov/oauth2/callback?code=test&state=test"
```

Expected:
- `/oauth2/start` -> `302` to Globus
- test callback often `500` (fake code/state); this is normal

### Real user flow

1. Open `https://mlflow.alcf.anl.gov/` in a private/incognito window.
2. Sign in via Globus.
3. Confirm MLflow UI loads.

## 5) Access Control

- Allowlist source:
  - `OAUTH2_PROXY_ALLOWED_EMAILS` in `server/.env`
- Generated file:
  - `server/runtime/generated/oauth2-proxy-allowed-emails.txt`
- Current allowed users:
  - `huihuo.zheng@anl.gov`
  - `venkat@anl.gov`
  - `turam@anl.gov`

After allowlist changes:

```bash
bash server/setup_globus_auth.sh
sudo systemctl restart oauth2-proxy
```

## 6) Known Failure Patterns

- `404` on `/oauth2/*`:
  - External nginx is routing `/oauth2/*` to MLflow instead of oauth2-proxy.
- `502 Bad Gateway` on callback:
  - nginx cannot reach upstream `:8081` or `:8080`, or upstream headers too large.
- `upstream sent too big header`:
  - Increase nginx proxy header buffers (already included in generated `mlflow.conf`).
- `CSRF cookie not found` / callback auth failures:
  - Browser/session/cookie issues or callback retries; retry in fresh private window.

## 7) Logs for Triage

```bash
journalctl -u oauth2-proxy -n 200 --no-pager
journalctl -u mlflow-globus -n 200 --no-pager
sudo tail -n 120 /var/log/nginx/error.log
```

## 8) Quick Recovery

```bash
# regenerate configs
bash server/setup_globus_auth.sh
bash server/setup_external_nginx_conf.sh

# restart services
sudo systemctl restart oauth2-proxy
sudo systemctl restart mlflow-globus
sudo nginx -t && sudo systemctl reload nginx
```

## 9) References

- Architecture: `docs/mlflow-globus-architecture.md`
- Diagram: `docs/mlflow-globus-architecture.svg`
