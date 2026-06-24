#!/usr/bin/env bash
set -eo pipefail

NAMESPACE="exercise24"
TABLE_NAME="exercise24-customers"
REGION="ap-south-1"

echo "============================================="
echo "Running validation checks for Exercise 24"
echo "============================================="

echo "1. Checking ServiceAccount details:"
kubectl get sa customer-sa -n "$NAMESPACE" -o yaml

echo -e "\n2. Checking deployment and pods status:"
kubectl get deploy,pods -n "$NAMESPACE"

echo -e "\n3. Describing target DynamoDB table in AWS:"
aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$REGION" --query "Table.[TableStatus, ItemCount, TableSizeBytes]"

echo -e "\n4. Scanning DynamoDB Table for items:"
aws dynamodb scan --table-name "$TABLE_NAME" --region "$REGION"

echo "============================================="
echo "Validation finished!"
echo "============================================="
