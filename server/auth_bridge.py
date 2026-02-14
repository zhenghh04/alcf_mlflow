#!/usr/bin/env python3
"""
Identity bridge for MLflow basic-auth app behind oauth2-proxy/nginx.

This authorization function allows:
1) normal MLflow Basic Auth (for automation/admin APIs)
2) trusted header-based identity (e.g., X-Email) from reverse proxy

Set in server/.env:
  MLFLOW_AUTH_AUTHORIZATION_FUNCTION=auth_bridge:authenticate_request_globus_header
"""

from __future__ import annotations

import os
import secrets
from functools import lru_cache

from mlflow.exceptions import MlflowException
from mlflow.server.auth import Authorization, make_basic_auth_response, request, store


@lru_cache(maxsize=1)
def _settings() -> dict[str, object]:
    raw_admins = os.getenv("MLFLOW_BRIDGE_ADMIN_EMAILS", "")
    admins = {
        x.strip().lower()
        for x in raw_admins.split(",")
        if x.strip()
    }
    return {
        "header": os.getenv("MLFLOW_BRIDGE_USER_HEADER", "X-Email"),
        "required_secret": os.getenv("MLFLOW_BRIDGE_SHARED_SECRET", ""),
        "secret_header": os.getenv("MLFLOW_BRIDGE_SECRET_HEADER", "X-Bridge-Secret"),
        "auto_create": os.getenv("MLFLOW_BRIDGE_AUTO_CREATE_USERS", "true").lower() == "true",
        # Safer default: only allow Basic Auth fallback from localhost.
        "basic_local_only": os.getenv("MLFLOW_BRIDGE_ALLOW_BASIC_FALLBACK_LOCAL_ONLY", "true").lower() == "true",
        "trusted_local_addrs": {
            x.strip().lower()
            for x in os.getenv("MLFLOW_BRIDGE_TRUSTED_LOCAL_ADDRS", "127.0.0.1,::1,localhost").split(",")
            if x.strip()
        },
        "admins": admins,
    }


def _find_or_create_user(username: str, is_admin: bool) -> None:
    try:
        store.get_user(username)
        return
    except Exception:
        pass

    # Random password is not used for header-based login but keeps DB consistent.
    password = secrets.token_urlsafe(24)
    try:
        store.create_user(username=username, password=password, is_admin=is_admin)
    except MlflowException:
        # Safe to ignore race/duplicate from concurrent requests.
        pass


def authenticate_request_globus_header():
    """
    Authorization function compatible with MLflow's basic-auth app.

    Priority:
    1) If trusted proxy identity header is present, use it.
    2) Otherwise fall back to HTTP Basic credentials for trusted local callers.
    """
    cfg = _settings()
    identity_header = str(cfg["header"])
    username = (request.headers.get(identity_header) or "").strip().lower()
    if username:
        required_secret = str(cfg["required_secret"])
        if required_secret:
            secret_header = str(cfg["secret_header"])
            presented = (request.headers.get(secret_header) or "").strip()
            if presented != required_secret:
                return make_basic_auth_response()

        is_admin = username in cfg["admins"]
        if bool(cfg["auto_create"]):
            _find_or_create_user(username, is_admin)

        return Authorization("basic", {"username": username, "password": None})

    # Keep Basic Auth behavior for local scripts/admin API use when no bridge header exists.
    if request.authorization is not None:
        if bool(cfg["basic_local_only"]):
            remote_addr = (request.remote_addr or "").strip().lower()
            if remote_addr not in cfg["trusted_local_addrs"]:
                return make_basic_auth_response()
        username = request.authorization.username
        password = request.authorization.password
        if username and password and store.authenticate_user(username, password):
            return request.authorization

    return make_basic_auth_response()
