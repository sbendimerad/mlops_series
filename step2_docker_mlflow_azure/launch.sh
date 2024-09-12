#!/bin/bash

echo "Starting MLflow Tracking Server ..."
mlflow server \
    --backend-store-uri "$MLFLOW_BACKEND_STORE_URI" \
    --default-artifact-root "$MLFLOW_SERVER_DEFAULT_ARTIFACT_ROOT" \
    --host "$MLFLOW_SERVER_HOST" \
    --port "$MLFLOW_SERVER_PORT" \
    --workers "$MLFLOW_SERVER_WORKERS"
