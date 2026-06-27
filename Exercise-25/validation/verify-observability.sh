#!/usr/bin/env bash
set -eo pipefail

NAMESPACE="observability"

echo "============================================="
echo "Running Validation for Observability Stack (Exercise 25)"
echo "============================================="

echo "1. Checking Pod status in namespace '$NAMESPACE':"
kubectl get pods -n "$NAMESPACE" -o wide

echo -e "\n2. Checking Service endpoints in namespace '$NAMESPACE':"
kubectl get svc -n "$NAMESPACE"

echo -e "\n3. Checking ConfigMaps for Dashboards:"
kubectl get configmaps -n "$NAMESPACE" | grep -E "dashboard|config"

echo -e "\n4. Checking Grafana Secret and Login details:"
GRAFANA_PASS=$(kubectl get secret --namespace "$NAMESPACE" grafana -o jsonpath="{.data.admin-password}" | base64 --decode || echo "admin")
echo "Grafana URL: http://localhost:3000"
echo "Username: admin"
echo "Password: $GRAFANA_PASS"

echo -e "\n5. Verifying API connectivity via local Port-Forward (Dry Run test):"
kubectl port-forward svc/prometheus-server 9090:80 -n "$NAMESPACE" > /dev/null 2>&1 &
PF_PROM=$!
sleep 2
echo -n "Prometheus API response: "
curl -s "http://127.0.0.1:9090/api/v1/targets" | grep -q "status" && echo "SUCCESS" || echo "FAILED"
kill $PF_PROM || true

kubectl port-forward svc/loki 3100:3100 -n "$NAMESPACE" > /dev/null 2>&1 &
PF_LOKI=$!
sleep 2
echo -n "Loki API readiness response: "
curl -s "http://127.0.0.1:3100/ready" | grep -q "ready" && echo "SUCCESS" || echo "FAILED"
kill $PF_LOKI || true

echo "============================================="
echo "Validation Checks Finished!"
echo "============================================="
