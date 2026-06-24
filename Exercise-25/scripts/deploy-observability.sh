#!/usr/bin/env bash
set -euo pipefail

# Navigation to script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

NAMESPACE="observability"

echo "============================================="
echo "Starting deployment for Observability Stack (Exercise 25)"
echo "============================================="

# 1. Create Namespace
echo "--> Creating Namespace '$NAMESPACE'..."
kubectl apply -f "$BASE_DIR/manifests/namespace.yaml"

# 2. Add Helm Repositories
echo "--> Adding Helm Repositories..."
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# 3. Deploy Alloy Configuration
echo "--> Applying Grafana Alloy configuration..."
kubectl apply -f "$BASE_DIR/manifests/alloy-config.yaml"

# 4. Deploy Prometheus Server
echo "--> Deploying Prometheus Server..."
helm upgrade --install prometheus-server prometheus-community/prometheus \
  --namespace "$NAMESPACE" \
  -f "$BASE_DIR/helm/prometheus-values.yaml"

# 5. Deploy Loki
echo "--> Deploying Grafana Loki..."
helm upgrade --install loki grafana/loki \
  --namespace "$NAMESPACE" \
  -f "$BASE_DIR/helm/loki-values.yaml"

# 6. Deploy Tempo
echo "--> Deploying Grafana Tempo..."
helm upgrade --install tempo grafana/tempo \
  --namespace "$NAMESPACE" \
  -f "$BASE_DIR/helm/tempo-values.yaml"

# 7. Apply Dashboards ConfigMaps
echo "--> Applying Grafana Dashboard ConfigMaps..."
kubectl apply -f "$BASE_DIR/manifests/grafana-dashboards/dashboards.yaml"

# 8. Deploy Grafana
echo "--> Deploying Grafana..."
helm upgrade --install grafana grafana/grafana \
  --namespace "$NAMESPACE" \
  -f "$BASE_DIR/helm/grafana-values.yaml"

# 9. Deploy Grafana Alloy Collector (using Helm or manifest, let's deploy Alloy collector)
echo "--> Deploying Grafana Alloy Collector..."
helm upgrade --install alloy grafana/alloy \
  --namespace "$NAMESPACE" \
  --set alloy.configMap.name=alloy-config \
  --set alloy.configMap.key=config.alloy

echo "============================================="
echo "Observability Stack Deployment Triggered!"
echo "Run verification script: ./validation/verify-observability.sh"
echo "============================================="
