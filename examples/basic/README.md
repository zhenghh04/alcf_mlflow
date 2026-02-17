# Basic MLflow Example

This is the minimal tracking example using MLflow.

Script:

- `log_example.py`

What it logs:

- Params: `learning_rate`, `epochs`
- Metric over steps: `loss`

## Prerequisites

From `mlflow/`:

```bash
cp examples/.env.example examples/.env
```

Required in `examples/.env`:

- `MLFLOW_TRACKING_URI`
- `AM_SC_API_KEY`

Optional:

- `MLFLOW_TRACKING_INSECURE_TLS` (defaults to `true` in script)

## Run

```bash
cd ../../
source server/venv/bin/activate
python examples/basic/log_example.py
```

## Verify in MLflow UI

1. Open experiment `alcf-vm-smoke-test`.
2. Open the latest run.
3. Check Parameters and Metrics for `learning_rate`, `epochs`, and `loss`.
