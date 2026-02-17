# W&B to MLflow Migration

This folder supports two different migration goals:

1. Convert existing W&B run logs into MLflow runs.
2. Translate W&B-style logging code into MLflow-style logging code.

## Scripts

- `wandb2mlflow_conversion.py`: converts existing W&B run data to MLflow.
- `wandb2mlflow_translation.py`: runnable code-translation example (W&B logging pattern -> MLflow logging pattern).

## Setup

From `mlflow/`:

```bash
cp examples/.env.example examples/.env
source server/venv/bin/activate
python -m pip install wandb
```

Required keys in `examples/.env`:

- `MLFLOW_TRACKING_URI`
- `AM_SC_API_KEY`

Additional keys by workflow:

- Conversion via W&B API: `WANDB_API_KEY`
- Optional defaults: `WANDB_RUN_PATH`, `MLFLOW_EXPERIMENT_NAME`

## Workflow A: Convert Existing W&B Runs

Use `wandb2mlflow_conversion.py`.

### Option A1: Convert directly from W&B API

```bash
cd ../../
source server/venv/bin/activate
python examples/migration/wandb2mlflow_conversion.py --wandb-run-path "<entity>/<project>/<run_id>"
```

### Option A2: Convert from exported W&B files

```bash
cd ../../
source server/venv/bin/activate
python examples/migration/wandb2mlflow_conversion.py \
  --history-csv /path/to/wandb_history.csv \
  --summary-json /path/to/wandb_summary.json \
  --config-json /path/to/wandb_config.json
```

What this conversion logs to MLflow:

- Config values as params
- History numeric fields as metrics (step-aware)
- Summary numeric fields as `summary/*` metrics
- Source metadata artifact: `wandb/source_metadata.json`
- Input files under `wandb/raw` (file mode)

## Workflow B: Translate W&B Logging Code to MLflow

Use `wandb2mlflow_translation.py`.

```bash
cd ../../
source server/venv/bin/activate
python examples/migration/wandb2mlflow_translation.py --epochs 3
```

This script demonstrates direct API mapping.

W&B style:

```python
run = wandb.init(project="demo", config=vars(args))
wandb.log({"train/loss": loss, "train/acc": acc, "epoch": epoch})
run.finish()
```

MLflow style:

```python
mlflow.set_experiment("demo")
with mlflow.start_run():
    mlflow.log_params(vars(args))
    mlflow.log_metric("train/loss", loss, step=epoch)
    mlflow.log_metric("train/acc", acc, step=epoch)
    mlflow.log_metric("epoch", epoch, step=epoch)
```

Mapping summary:

- `wandb.init(project=..., config=...)` -> `mlflow.set_experiment(...)` + `mlflow.start_run(...)` + `mlflow.log_params(...)`
- `wandb.log({...})` -> `mlflow.log_metric(...)` for each metric key
- `wandb.config` -> `mlflow.log_param(...)` / `mlflow.log_params(...)`
- `wandb.run.summary[...]` -> final metrics/tags/artifacts in MLflow
- `wandb.finish()` -> end of `with mlflow.start_run():`

Translation demo artifact:

- `translation/summary.json`
