#!/usr/bin/env bash
set -eo pipefail

TABLE_NAME="exercise24-customers"
REGION="ap-south-1"

echo "============================================="
echo "Creating DynamoDB Table: $TABLE_NAME"
echo "============================================="

# Create table
aws dynamodb create-table \
  --table-name "$TABLE_NAME" \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$REGION" || echo "Table already exists or creation failed."

echo "--> Describing table state:"
aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$REGION" --query "Table.TableStatus"

echo "============================================="
echo "Done!"
echo "============================================="
