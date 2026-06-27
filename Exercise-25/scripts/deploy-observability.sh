#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

NAMESPACE="observability"

echo "============================================="
echo "Starting deployment for Observability Stack (Exercise 25)"
echo "============================================="

echo "--> Creating Namespace '$NAMESPACE'..."
kubectl apply -f "$BASE_DIR/manifests/namespace.yaml"

echo "--> Adding Helm Repositories..."
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

echo "--> Applying Grafana Alloy configuration..."
kubectl apply -f "$BASE_DIR/manifests/alloy-config.yaml"

echo "--> Deploying Prometheus Server..."
helm upgrade --install prometheus-server prometheus-community/prometheus \
  --namespace "$NAMESPACE" \
  -f "$BASE_DIR/helm/prometheus-values.yaml"

echo "--> Deploying Grafana Loki..."
helm upgrade --install loki grafana/loki \
  --namespace "$NAMESPACE" \
  -f "$BASE_DIR/helm/loki-values.yaml"

echo "--> Deploying Grafana Tempo..."
helm upgrade --install tempo grafana/tempo \
  --namespace "$NAMESPACE" \
  -f "$BASE_DIR/helm/tempo-values.yaml"

echo "--> Applying Grafana Dashboard ConfigMaps..."
kubectl apply -f "$BASE_DIR/manifests/grafana-dashboards/dashboards.yaml"

echo "--> Deploying Grafana..."
helm upgrade --install grafana grafana/grafana \
  --namespace "$NAMESPACE" \
  -f "$BASE_DIR/helm/grafana-values.yaml"

echo "--> Deploying Grafana Alloy Collector..."
helm upgrade --install alloy grafana/alloy \
  --namespace "$NAMESPACE" \
  --set alloy.configMap.name=alloy-config \
  --set alloy.configMap.key=config.alloy

echo "============================================="
echo "Observability Stack Deployment Triggered!"
echo "Run verification script: ./validation/verify-observability.sh"
echo "============================================="
