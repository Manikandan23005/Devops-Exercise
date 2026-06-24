#!/usr/bin/env bash
set -eo pipefail

NAMESPACE="exercise22"

echo "============================================="
echo "Verifying Autoscaling status for Exercise 22"
echo "============================================="

# 1. Verify Metrics Server Integration
echo "1. Checking if Metrics API is responding:"
if kubectl get --raw /apis/metrics.k8s.io/v1beta1 > /dev/null 2>&1; then
  echo "SUCCESS: Metrics API is available."
else
  echo "WARNING: Metrics API v1beta1 is NOT available. Let's list general APIServices:"
  kubectl get apiservice | grep metrics || true
fi

# 2. Check HPA status
echo -e "\n2. Fetching HPA details:"
kubectl get hpa cpu-load-hpa -n "$NAMESPACE"

# 3. Check Pod Resource Utilization
echo -e "\n3. Fetching CPU and Memory usage per pod:"
kubectl top pods -n "$NAMESPACE" || echo "Unable to fetch pod metrics (Metrics Server may still be initializing or unavailable)"

# 4. Check Node Resource Utilization
echo -e "\n4. Fetching CPU and Memory usage per node:"
kubectl top nodes || echo "Unable to fetch node metrics"

# 5. Check Node Count
echo -e "\n5. Active Cluster Nodes count:"
kubectl get nodes -o wide

# 6. Check Cluster Autoscaler deployment logs
echo -e "\n6. Checking Cluster Autoscaler deployment status:"
kubectl get deploy cluster-autoscaler -n kube-system || echo "Cluster Autoscaler deployment not found in kube-system"

echo -e "\n7. Recent Cluster Autoscaler Logs (first 10 lines):"
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=15 || echo "No logs available"

echo "============================================="
echo "Verification Script Finished!"
echo "============================================="
