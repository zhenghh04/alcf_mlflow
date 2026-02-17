#!/usr/bin/env python3
import json
import os
import time
from datetime import datetime, timezone
from pathlib import Path

import mlflow
from openai import OpenAI


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


def _get_usage_field(usage, field_name):
    value = getattr(usage, field_name, None)
    if value is not None:
        return int(value)
    if isinstance(usage, dict):
        return int(usage.get(field_name, 0))
    return 0


def _load_prompts():
    prompts_json = os.environ.get("OPENAI_PROMPTS_JSON", "").strip()
    if prompts_json:
        parsed = json.loads(prompts_json)
        if isinstance(parsed, list) and all(isinstance(item, str) for item in parsed) and parsed:
            return parsed
        raise ValueError("OPENAI_PROMPTS_JSON must be a non-empty JSON list of strings.")

    return [
        "Summarize why experiment tracking is useful for LLM applications in 2 sentences.",
        "Give 3 practical metrics to monitor in an LLM application run.",
        "Write one concise prompt-engineering tip for reducing hallucinations.",
    ]


def main():
    load_examples_env()
    os.environ.setdefault("MLFLOW_TRACKING_INSECURE_TLS", "true")
    configure_insecure_tls_warnings()
    enable_amsc_x_api_key()
    tracking_uri = os.environ.get("MLFLOW_TRACKING_URI", DEFAULT_TRACKING_URI)
    experiment_name = os.environ.get("MLFLOW_EXPERIMENT_NAME", "alcf-vm-openai-tracking")
    model = os.environ.get("OPENAI_MODEL", "gpt-4o-mini")
    prompts = _load_prompts()

    if not os.environ.get("OPENAI_API_KEY"):
        raise RuntimeError("OPENAI_API_KEY is required to run this example.")

    mlflow.set_tracking_uri(tracking_uri)
    mlflow.set_experiment(experiment_name)
    mlflow.openai.autolog(log_traces=True, silent=True)

    client = OpenAI()

    run_name = f"openai-prompt-{datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')}"
    with mlflow.start_run(run_name=run_name):
        mlflow.set_tag("provider", "openai")
        mlflow.set_tag("model", model)
        mlflow.log_param("model", model)
        mlflow.log_param("temperature", 0.2)
        mlflow.log_param("num_questions", len(prompts))

        trace_rows = []
        total_prompt_tokens = 0
        total_completion_tokens = 0
        total_tokens = 0

        for idx, prompt in enumerate(prompts):
            start = time.perf_counter()
            response = client.responses.create(
                model=model,
                input=prompt,
                temperature=0.2,
            )
            latency_sec = time.perf_counter() - start

            output_text = getattr(response, "output_text", None) or ""
            usage = getattr(response, "usage", None)
            prompt_tokens = _get_usage_field(usage, "input_tokens")
            completion_tokens = _get_usage_field(usage, "output_tokens")
            row_total_tokens = _get_usage_field(usage, "total_tokens")

            total_prompt_tokens += prompt_tokens
            total_completion_tokens += completion_tokens
            total_tokens += row_total_tokens

            mlflow.log_metric("query_latency_sec", latency_sec, step=idx)
            mlflow.log_metric("query_prompt_tokens", prompt_tokens, step=idx)
            mlflow.log_metric("query_completion_tokens", completion_tokens, step=idx)
            mlflow.log_metric("query_total_tokens", row_total_tokens, step=idx)

            trace_rows.append(
                {
                    "index": idx,
                    "prompt": prompt,
                    "response": output_text,
                    "latency_sec": latency_sec,
                    "prompt_tokens": prompt_tokens,
                    "completion_tokens": completion_tokens,
                    "total_tokens": row_total_tokens,
                }
            )

        mlflow.log_metric("prompt_tokens_total", total_prompt_tokens)
        mlflow.log_metric("completion_tokens_total", total_completion_tokens)
        mlflow.log_metric("total_tokens_total", total_tokens)
        mlflow.log_dict({"trace": trace_rows}, "llm/trace/trace_summary.json")

    print(f"Logged OpenAI LLM run to {tracking_uri}")
    print(f"Model: {model}")
    print(f"Questions traced: {len(prompts)}")
    print(f"Prompt tokens total: {total_prompt_tokens}")
    print(f"Completion tokens total: {total_completion_tokens}")
    print(f"Total tokens total: {total_tokens}")


if __name__ == "__main__":
    main()
