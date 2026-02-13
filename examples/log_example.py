#!/usr/bin/env python3
import os
import random

import mlflow


tracking_uri = os.environ.get("MLFLOW_TRACKING_URI", "http://127.0.0.1:5000")
mlflow.set_tracking_uri(tracking_uri)
mlflow.set_experiment("alcf-vm-smoke-test")

with mlflow.start_run(run_name="quickstart"):
    lr = 0.01
    epochs = 3
    mlflow.log_param("learning_rate", lr)
    mlflow.log_param("epochs", epochs)

    loss = 1.0
    for step in range(epochs):
        loss *= random.uniform(0.6, 0.9)
        mlflow.log_metric("loss", loss, step=step)

print(f"Logged run to {tracking_uri}")
