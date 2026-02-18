#!/usr/bin/env python3
import argparse
import csv
import json
import math
import os
from pathlib import Path
from typing import Any

import mlflow


AMSC_API_KEY_ENV = "AM_SC_API_KEY"
DEFAULT_TRACKING_URI = "https://mlflow.american-science-cloud.org"


def configure_insecure_tls_warnings():
    insecure = os.environ.get("MLFLOW_TRACKING_INSECURE_TLS", "").strip().lower() in {"1", "true", "yes", "on"}
    if not insecure:
        return

    import urllib3
    from urllib3.exceptions import InsecureRequestWarning

    urllib3.disable_warnings(InsecureRequestWarning)


def load_examples_env():
    env_path = Path(__file__).resolve().parents[1] / ".env"
    if not env_path.exists():
        return

    for line in env_path.read_text(encoding="utf-8").splitlines():
        raw = line.strip()
        if not raw or raw.startswith("#") or "=" not in raw:
            continue
        key, value = raw.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        os.environ.setdefault(key, value)


def enable_amsc_x_api_key():
    if AMSC_API_KEY_ENV not in os.environ:
        return

    import mlflow.utils.rest_utils as rest_utils

    api_key = os.environ[AMSC_API_KEY_ENV]
    original_http_request = rest_utils.http_request

    def patched(host_creds, endpoint, method, *args, **kwargs):
        headers = dict(kwargs.get("extra_headers") or {})
        if kwargs.get("headers") is not None:
            headers.update(dict(kwargs["headers"]))
        headers["X-Api-Key"] = api_key
        kwargs["extra_headers"] = headers
        kwargs.pop("headers", None)
        return original_http_request(host_creds, endpoint, method, *args, **kwargs)

    rest_utils.http_request = patched


def parse_args():
    parser = argparse.ArgumentParser(description="Import W&B run tracking data into MLflow.")
    parser.add_argument(
        "--wandb-run-path",
        type=str,
        default=os.environ.get("WANDB_RUN_PATH", ""),
        help="W&B run path in form entity/project/run_id. If set, import via W&B API.",
    )
    parser.add_argument(
        "--history-csv",
        type=str,
        default="",
        help="Path to exported W&B history CSV (fallback mode when not using API).",
    )
    parser.add_argument(
        "--summary-json",
        type=str,
        default="",
        help="Path to exported W&B summary JSON (optional).",
    )
    parser.add_argument(
        "--config-json",
        type=str,
        default="",
        help="Path to exported W&B config JSON (optional).",
    )
    parser.add_argument(
        "--experiment-name",
        type=str,
        default=os.environ.get("MLFLOW_EXPERIMENT_NAME", "wandb-import"),
        help="MLflow experiment name.",
    )
    parser.add_argument(
        "--step-field",
        type=str,
        default="_step",
        help="Column name to use as metric step in history rows.",
    )
    return parser.parse_args()


def _is_finite_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(float(value))


def _to_float(value: Any):
    if value is None or isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return float(value) if math.isfinite(float(value)) else None
    if isinstance(value, str):
        text = value.strip()
        if not text:
            return None
        try:
            number = float(text)
            return number if math.isfinite(number) else None
        except ValueError:
            return None
    return None


def _to_step(value: Any, fallback_step: int) -> int:
    number = _to_float(value)
    if number is None:
        return fallback_step
    return int(number)


def _read_json(path: str) -> dict[str, Any]:
    if not path:
        return {}
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data if isinstance(data, dict) else {}


def _read_history_csv(path: str) -> list[dict[str, Any]]:
    rows = []
    with open(path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append(dict(row))
    return rows


def _sanitize_config(config: dict[str, Any]) -> dict[str, Any]:
    clean = {}
    for key, value in config.items():
        if key.startswith("_"):
            continue
        if isinstance(value, (str, int, float, bool)):
            clean[key] = value
        else:
            clean[key] = json.dumps(value, sort_keys=True)
    return clean


def _sanitize_key(key: str) -> str:
    return key.replace("/", "__").replace(" ", "_")


def _load_wandb_config_from_yaml(path: Path) -> dict[str, Any]:
    try:
        import yaml
    except ImportError:
        return {}

    try:
        raw = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except Exception:
        return {}

    if not isinstance(raw, dict):
        return {}

    config = {}
    for key, value in raw.items():
        if isinstance(value, dict) and "value" in value:
            config[key] = value["value"]
        else:
            config[key] = value
    return config


def _load_wandb_history_jsonl(path: Path) -> list[dict[str, Any]]:
    rows = []
    if not path.exists():
        return rows

    with path.open("r", encoding="utf-8") as f:
        for line in f:
            text = line.strip()
            if not text:
                continue
            try:
                obj = json.loads(text)
                if isinstance(obj, dict):
                    rows.append(obj)
            except json.JSONDecodeError:
                continue
    return rows


def _load_from_wandb_local_dir(run_dir: str):
    base = Path(run_dir).expanduser().resolve()
    if not base.exists() or not base.is_dir():
        raise ValueError(f"Local W&B run directory not found: {run_dir}")

    files_dir = base / "files"
    summary_path = files_dir / "wandb-summary.json"
    config_yaml_path = files_dir / "config.yaml"
    history_jsonl_path = files_dir / "wandb-history.jsonl"

    summary = {}
    if summary_path.exists():
        try:
            parsed = json.loads(summary_path.read_text(encoding="utf-8"))
            if isinstance(parsed, dict):
                summary = parsed
        except Exception:
            summary = {}

    config = {}
    if config_yaml_path.exists():
        config = _load_wandb_config_from_yaml(config_yaml_path)

    history_rows = _load_wandb_history_jsonl(history_jsonl_path)
    tags = []

    # dirname usually looks like run-YYYYMMDD_HHMMSS-<run_id>
    parts = base.name.split("-")
    inferred_run_id = parts[-1] if len(parts) >= 3 else base.name
    run_name = f"wandb-local-import-{inferred_run_id}"
    metadata = {
        "source": "wandb_local_dir",
        "local_run_dir": str(base),
        "inferred_run_id": inferred_run_id,
        "summary_file_found": summary_path.exists(),
        "config_file_found": config_yaml_path.exists(),
        "history_file_found": history_jsonl_path.exists(),
    }

    if not summary and not config and not history_rows:
        raise ValueError(
            "No usable W&B files found in local run directory. "
            f"Expected files under {files_dir}: wandb-summary.json, config.yaml, wandb-history.jsonl"
        )

    return run_name, _sanitize_config(config), summary, history_rows, tags, metadata


def _load_from_wandb_api(run_path: str):
    import wandb

    api = wandb.Api()
    run = api.run(run_path)
    config = _sanitize_config(dict(run.config))
    summary = dict(run.summary._json_dict)
    history_rows = [dict(row) for row in run.scan_history()]
    tags = list(run.tags or [])
    run_name = run.name or Path(run.path[-1]).name
    metadata = {
        "run_id": run.id,
        "entity": run.entity,
        "project": run.project,
        "url": run.url,
        "state": run.state,
        "created_at": str(run.created_at),
    }
    return run_name, config, summary, history_rows, tags, metadata


def _load_from_files(history_csv: str, summary_json: str, config_json: str):
    if not history_csv:
        raise ValueError("Either --wandb-run-path or --history-csv must be provided.")
    config = _sanitize_config(_read_json(config_json))
    summary = _read_json(summary_json)
    history_rows = _read_history_csv(history_csv)
    run_name = f"wandb-file-import-{Path(history_csv).stem}"
    tags = []
    metadata = {"source_history_csv": history_csv, "source_summary_json": summary_json, "source_config_json": config_json}
    return run_name, config, summary, history_rows, tags, metadata


def main():
    args = parse_args()
    load_examples_env()
    os.environ.setdefault("MLFLOW_TRACKING_INSECURE_TLS", "true")
    configure_insecure_tls_warnings()
    enable_amsc_x_api_key()

    if args.wandb_run_path:
        path_candidate = Path(args.wandb_run_path).expanduser()
        if path_candidate.exists() and path_candidate.is_dir():
            run_name, config, summary, history_rows, tags, metadata = _load_from_wandb_local_dir(args.wandb_run_path)
            source = "wandb_local_dir"
        else:
            run_name, config, summary, history_rows, tags, metadata = _load_from_wandb_api(args.wandb_run_path)
            source = "wandb_api"
    else:
        run_name, config, summary, history_rows, tags, metadata = _load_from_files(
            args.history_csv, args.summary_json, args.config_json
        )
        source = "wandb_export_files"

    tracking_uri = os.environ.get("MLFLOW_TRACKING_URI", DEFAULT_TRACKING_URI)
    mlflow.set_tracking_uri(tracking_uri)
    mlflow.set_experiment(args.experiment_name)

    with mlflow.start_run(run_name=run_name):
        mlflow.log_param("conversion_source", source)
        if args.wandb_run_path:
            mlflow.log_param("conversion_wandb_run_path", args.wandb_run_path)
        for tag in tags:
            mlflow.log_param(f"wandb_tag__{_sanitize_key(tag)}", "true")

        for key, value in config.items():
            mlflow.log_param(key, value)

        for i, row in enumerate(history_rows):
            step = _to_step(row.get(args.step_field), i)
            for key, value in row.items():
                if key.startswith("_") or key == args.step_field:
                    continue
                num = _to_float(value)
                if num is not None:
                    mlflow.log_metric(key, num, step=step)

        for key, value in summary.items():
            if key.startswith("_"):
                continue
            if _is_finite_number(value):
                mlflow.log_metric(f"summary/{key}", float(value))
            elif isinstance(value, (str, bool)):
                mlflow.log_param(f"summary__{_sanitize_key(key)}", str(value))

        mlflow.log_dict(metadata, "wandb/source_metadata.json")
        if args.history_csv:
            mlflow.log_artifact(args.history_csv, artifact_path="wandb/raw")
        if args.summary_json:
            mlflow.log_artifact(args.summary_json, artifact_path="wandb/raw")
        if args.config_json:
            mlflow.log_artifact(args.config_json, artifact_path="wandb/raw")

    print(f"Imported W&B tracking data into MLflow: {tracking_uri}")
    print(f"Experiment: {args.experiment_name}")
    print(f"Run name: {run_name}")
    print(f"History rows imported: {len(history_rows)}")


if __name__ == "__main__":
    main()
