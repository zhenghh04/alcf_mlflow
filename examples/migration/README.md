# W&B to MLflow Migration Example

This example imports W&B tracking data into MLflow.

Script:

- `wandb2mlflow.py`
- `wandb_to_mlflow_translation.py`

Import modes:

1. W&B API mode with `--wandb-run-path <entity>/<project>/<run_id>`
2. File mode with exported W&B files:
   - `--history-csv`
   - optional `--summary-json`
   - optional `--config-json`

## Prerequisites

From `mlflow/`:

```bash
cp examples/.env.example examples/.env
```

Required in `examples/.env`:

- `MLFLOW_TRACKING_URI`
- `AM_SC_API_KEY`

For API mode:

- `WANDB_API_KEY` (or export before running)

Optional:

- `WANDB_RUN_PATH`
- `MLFLOW_EXPERIMENT_NAME` (defaults to `wandb-import`)

Install dependency:

```bash
source server/venv/bin/activate
python -m pip install wandb
```

## Run (API mode)

```bash
cd ../../
source server/venv/bin/activate
python examples/migration/wandb2mlflow.py --wandb-run-path "<entity>/<project>/<run_id>"
```

## Run (file mode)

```bash
cd ../../
source server/venv/bin/activate
python examples/migration/wandb2mlflow.py \
  --history-csv /path/to/wandb_history.csv \
  --summary-json /path/to/wandb_summary.json \
  --config-json /path/to/wandb_config.json
```

## Run (translation example: W&B style -> MLflow style)

```bash
cd ../../
source server/venv/bin/activate
python examples/migration/wandb_to_mlflow_translation.py --epochs 3
```

## W&B to MLflow Call Translation

W&B:

```python
run = wandb.init(project="demo", config=vars(args))
wandb.log({"train/loss": loss, "train/acc": acc, "epoch": epoch})
run.finish()
```

MLflow equivalent:

```python
mlflow.set_experiment("demo")
with mlflow.start_run():
    mlflow.log_params(vars(args))
    mlflow.log_metric("train/loss", loss, step=epoch)
    mlflow.log_metric("train/acc", acc, step=epoch)
    mlflow.log_metric("epoch", epoch, step=epoch)
```

Common mapping:

- `wandb.init(project=..., config=...)` -> `mlflow.set_experiment(...)` + `mlflow.start_run(...)` + `mlflow.log_params(...)`
- `wandb.log({...})` -> `mlflow.log_metric(...)` (repeat per key, with `step`)
- `wandb.config` -> MLflow params (`mlflow.log_param(s)`)
- `wandb.run.summary[...]` -> final metrics/tags/artifacts in MLflow
- `wandb.finish()` -> end of `with mlflow.start_run():` block

## What gets logged to MLflow

- Config values as params
- History numeric fields as metrics (step-aware)
- Summary numeric fields as `summary/*` metrics
- Source metadata artifact: `wandb/source_metadata.json`
- Input files as artifacts under `wandb/raw` (file mode)
- Translation demo summary artifact: `translation/summary.json`
