#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="exercise22"
SERVICE_NAME="cpu-load-service"
LOCAL_PORT=8080
TARGET_PATH="/load?duration=2.0&iterations=500000"

echo "============================================="
echo "Starting Load Test Setup for Exercise 22"
echo "============================================="

echo "--> Checking if service $SERVICE_NAME is available..."
kubectl get svc "$SERVICE_NAME" -n "$NAMESPACE"

echo "--> Establishing Port-Forward on port $LOCAL_PORT..."
kubectl port-forward svc/"$SERVICE_NAME" "$LOCAL_PORT":80 -n "$NAMESPACE" > /dev/null 2>&1 &
PF_PID=$!

cleanup() {
  echo "--> Cleaning up port forward (PID: $PF_PID)..."
  kill "$PF_PID" || true
}
trap cleanup EXIT

sleep 3

echo -e "\n=== OPTION 1: Using 'hey' (HTTP load generator) ==="
echo "Running hey load generator: 50 concurrent users for 60 seconds"
if command -v hey &> /dev/null; then
  hey -z 60s -c 50 "http://127.0.0.1:$LOCAL_PORT$TARGET_PATH"
else
  echo "INFO: 'hey' is not installed. Example command:"
  echo "hey -z 60s -c 50 \"http://127.0.0.1:$LOCAL_PORT$TARGET_PATH\""
fi

echo -e "\n=== OPTION 2: Using 'ab' (Apache Benchmark) ==="
echo "Running Apache Benchmark: 1000 requests, concurrency of 10"
if command -v ab &> /dev/null; then
  ab -n 1000 -c 10 "http://127.0.0.1:$LOCAL_PORT/load?duration=0.5"
else
  echo "INFO: 'ab' is not installed. Example command:"
  echo "ab -n 1000 -c 10 \"http://127.0.0.1:$LOCAL_PORT/load?duration=0.5\""
fi

echo -e "\n=== OPTION 3: Running k6 Load Test ==="
echo "Example command to execute the k6 script:"
echo "k6 run scripts/load-test-k6.js"

echo -e "\n--> Load test execution finished. Monitoring scaling..."
echo "Watch pods scale up using: kubectl get pods -n $NAMESPACE -w"
echo "Waiting 10 seconds before shutting down..."
sleep 10
