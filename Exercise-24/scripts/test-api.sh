#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="exercise24"
SERVICE_NAME="customer-service"
LOCAL_PORT=5000

echo "============================================="
echo "Running API Integration Tests for Exercise 24"
echo "============================================="

# 1. Verify STS AssumeRole Inside the Pod
echo "--> Verifying Pod AWS STS caller identity (assumed IRSA Role):"
POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app=customer-app -o jsonpath='{.items[0].metadata.name}')
echo "Target Pod: $POD_NAME"

kubectl exec -it "$POD_NAME" -n "$NAMESPACE" -c app -- pip install awscli --target /app/libs > /dev/null 2>&1 || true
kubectl exec -it "$POD_NAME" -n "$NAMESPACE" -c app -- sh -c "PYTHONPATH=/app/libs python -m awscli sts get-caller-identity" || {
  echo "awscli not installed in pod, running test via boto3 environment check:"
  kubectl exec -it "$POD_NAME" -n "$NAMESPACE" -c app -- python -c "
import boto3
sts = boto3.client('sts')
print(sts.get_caller_identity())
"
}

# 2. Setup Port Forward
echo -e "\n--> Port-forwarding $SERVICE_NAME to localhost:$LOCAL_PORT..."
kubectl port-forward svc/"$SERVICE_NAME" "$LOCAL_PORT":80 -n "$NAMESPACE" > /dev/null 2>&1 &
PF_PID=$!

cleanup() {
  echo "--> Terminating port-forward..."
  kill "$PF_PID" || true
}
trap cleanup EXIT

sleep 3

# 3. Create Customer (POST /customer)
echo -e "\n--> 1. Testing POST /customer (Write):"
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"id": "c101", "name": "Manikandan", "email": "mani@example.com", "phone": "123456789"}' \
  "http://127.0.0.1:$LOCAL_PORT/customer" | json_pp || curl -s -X POST -H "Content-Type: application/json" \
  -d '{"id": "c101", "name": "Manikandan", "email": "mani@example.com", "phone": "123456789"}' \
  "http://127.0.0.1:$LOCAL_PORT/customer"

# 4. Read Customer (GET /customer/c101)
echo -e "\n--> 2. Testing GET /customer/c101 (Read):"
curl -s "http://127.0.0.1:$LOCAL_PORT/customer/c101" | json_pp || curl -s "http://127.0.0.1:$LOCAL_PORT/customer/c101"

# 5. Update Customer (PUT /customer/c101)
echo -e "\n--> 3. Testing PUT /customer/c101 (Update):"
curl -s -X PUT -H "Content-Type: application/json" \
  -d '{"name": "Mani Satoru", "email": "satoru@example.com"}' \
  "http://127.0.0.1:$LOCAL_PORT/customer/c101" | json_pp || curl -s -X PUT -H "Content-Type: application/json" \
  -d '{"name": "Mani Satoru", "email": "satoru@example.com"}' \
  "http://127.0.0.1:$LOCAL_PORT/customer/c101"

# 6. Read Customer again to verify update
echo -e "\n--> 4. Verifying Update (GET /customer/c101):"
curl -s "http://127.0.0.1:$LOCAL_PORT/customer/c101" | json_pp || curl -s "http://127.0.0.1:$LOCAL_PORT/customer/c101"

echo -e "\n============================================="
echo "Integration Tests Completed!"
echo "============================================="
