#!/usr/bin/env python3
import argparse
import os
import random
import time
from pathlib import Path

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
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


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
    parser = argparse.ArgumentParser(description="W&B -> MLflow API translation example.")
    parser.add_argument("--epochs", type=int, default=3)
    parser.add_argument("--learning-rate", type=float, default=1e-3)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--experiment-name", type=str, default="wandb-to-mlflow-translation")
    return parser.parse_args()


def main():
    args = parse_args()
    load_examples_env()
    os.environ.setdefault("MLFLOW_TRACKING_INSECURE_TLS", "true")
    configure_insecure_tls_warnings()
    enable_amsc_x_api_key()

    tracking_uri = os.environ.get("MLFLOW_TRACKING_URI", DEFAULT_TRACKING_URI)
    mlflow.set_tracking_uri(tracking_uri)
    mlflow.set_experiment(args.experiment_name)

    # W&B: run = wandb.init(project="demo", config=vars(args))
    # MLflow equivalent: start run + log params.
    with mlflow.start_run(run_name="translation-demo"):
        mlflow.log_params(
            {
                "epochs": args.epochs,
                "learning_rate": args.learning_rate,
                "batch_size": args.batch_size,
            }
        )
        mlflow.set_tag("source_framework", "wandb_translation_example")

        # W&B: wandb.log({"train/loss": loss, "train/acc": acc, "epoch": epoch})
        # MLflow equivalent: log_metric(..., step=epoch)
        loss = 1.0
        for epoch in range(args.epochs):
            time.sleep(0.05)
            loss *= random.uniform(0.65, 0.9)
            acc = random.uniform(0.7, 0.95)
            mlflow.log_metric("train/loss", loss, step=epoch)
            mlflow.log_metric("train/acc", acc, step=epoch)
            mlflow.log_metric("epoch", epoch, step=epoch)

        summary = {
            "final_loss": loss,
            "final_acc": acc,
            "note": "This run demonstrates direct translation from W&B logging calls to MLflow.",
        }
        mlflow.log_dict(summary, "translation/summary.json")

    print(f"Logged translation example to {tracking_uri}")
    print(f"Experiment: {args.experiment_name}")


if __name__ == "__main__":
    main()
