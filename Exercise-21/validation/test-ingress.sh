#!/usr/bin/env bash
set -eo pipefail

NAMESPACE="exercise21"

echo "============================================="
echo "Running Validation for Exercise 21"
echo "============================================="

echo "1. Checking Namespace Status:"
kubectl get ns "$NAMESPACE"

echo -e "\n2. Checking Deployments and Pods status:"
kubectl get deployments,pods -n "$NAMESPACE" -o wide

echo -e "\n3. Checking Services status:"
kubectl get svc -n "$NAMESPACE"

echo -e "\n4. Checking Ingress details:"
kubectl get ingress apps-ingress -n "$NAMESPACE"

echo -e "\n5. Checking AWS Load Balancer Controller Logs:"
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=20

echo -e "\n6. Fetching ALB Ingress Address (may take 2-3 minutes to provision):"
ALB_HOST=""
for i in {1..20}; do
  ALB_HOST=$(kubectl get ingress apps-ingress -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' || echo "")
  if [ -n "$ALB_HOST" ]; then
    echo "Found ALB Hostname: $ALB_HOST"
    break
  fi
  echo "Waiting for ALB Hostname to be assigned... (Attempt $i/20)"
  sleep 10
done

if [ -z "$ALB_HOST" ]; then
  echo "WARNING: ALB Hostname did not provision in time. You can view progress in the AWS ALB Console."
  echo "We will run local port-forward tests to verify service-level routing."
  
  echo -e "\nRunning local port-forward tests for verification:"
  
  kubectl port-forward svc/api-service 8081:80 -n "$NAMESPACE" > /dev/null 2>&1 &
  PF_PID_API=$!
  sleep 2
  echo -n "Testing api-service via Port-Forward (8081): "
  curl -s http://127.0.0.1:8081/api/index.html || echo "Failed"
  kill $PF_PID_API || true
  
  kubectl port-forward svc/admin-service 8082:80 -n "$NAMESPACE" > /dev/null 2>&1 &
  PF_PID_ADMIN=$!
  sleep 2
  echo -n "Testing admin-service via Port-Forward (8082): "
  curl -s http://127.0.0.1:8082/admin/index.html || echo "Failed"
  kill $PF_PID_ADMIN || true

  kubectl port-forward svc/dashboard-service 8083:80 -n "$NAMESPACE" > /dev/null 2>&1 &
  PF_PID_DASH=$!
  sleep 2
  echo -n "Testing dashboard-service via Port-Forward (8083): "
  curl -s http://127.0.0.1:8083/dashboard/index.html || echo "Failed"
  kill $PF_PID_DASH || true
else
  echo -e "\n7. Running curl routing tests against ALB:"
  echo -n "HTTP to HTTPS redirect test: "
  curl -I -s "http://$ALB_HOST/api/" | grep -i "location" || echo "Redirect not found or connection failed"

  echo -n "API Service Route test: "
  curl -k -s "https://$ALB_HOST/api/index.html" || echo "Failed"

  echo -n "Admin Service Route test: "
  curl -k -s "https://$ALB_HOST/admin/index.html" || echo "Failed"

  echo -n "Dashboard Service Route test: "
  curl -k -s "https://$ALB_HOST/dashboard/index.html" || echo "Failed"
fi

echo "============================================="
echo "Validation Checks Completed!"
echo "============================================="
