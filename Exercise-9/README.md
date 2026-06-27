# Exercise 9 – Prometheus Monitoring Failure

## Incident Overview

An alert was triggered: **Metrics disappeared** on Grafana (shows "No Data").
Checking Prometheus shows the target `payment-service` is in a **DOWN** state, and Prometheus logs show:

```text
ts=2026-06-27T03:00:00Z level=warn msg="append failed" err="context deadline exceeded"
```

### Context Mismatch
* **ServiceMonitor:**
  ```yaml
  endpoints:
    - port: metrics
  ```
* **Service:**
  ```yaml
  ports:
    - name: prometheus # Working metrics port (8080)
      port: 8080
      targetPort: 8080
    - name: metrics # Broken/hanging port (9090)
      port: 9090
      targetPort: 9090
  ```

---

## 🛠️ Step 1: Lab Setup (Create Scenario)

Run the following commands to provision the stack and simulate the failure state:

### 1. Create the `payment` namespace
```bash
kubectl create namespace payment
```

### 2. Install the Prometheus Operator Stack (if not already running)
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.adminPassword=admin \
  --set prometheus.prometheusSpec.scrapeInterval=5s
```

### 3. Deploy the application, service, and service monitor
```bash
kubectl apply -f manifests/deployment.yaml
kubectl apply -f manifests/service.yaml
kubectl apply -f manifests/servicemonitor.yaml
```

### 4. Verify deployment and port-forward Prometheus
Wait a few seconds for the pods to run, then port-forward Prometheus:
```bash
# Wait for pods
kubectl wait --for=condition=Ready pod -l app=payment-service -n payment --timeout=60s

# Port-forward Prometheus
kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090
```
Open **[http://localhost:9090/targets](http://localhost:9090/targets)** in your browser. You will see `payment/payment-service-monitor` targets listed as **DOWN** with the error `context deadline exceeded`.

---

## 🔍 Step 2: Troubleshooting (Find the Mismatch)

Run these queries to diagnose the target:

### 1. Inspect the ServiceMonitor configuration
Check which port the ServiceMonitor is targeting:
```bash
kubectl get servicemonitor payment-service-monitor -n payment -o yaml | grep -A 2 endpoints
```
*Expected Output:* Shows `port: metrics`.

### 2. Inspect the Service configuration
Check what ports are defined on the Service and what container ports they point to:
```bash
kubectl get svc payment-service -n payment -o yaml
```
*Expected Output:*
* Port `prometheus` maps to `8080` (actual app).
* Port `metrics` maps to `9090` (hanging port).

### 3. Inspect Pod Logs (Verify port behavior)
Check python stdout to confirm both servers are listening:
```bash
kubectl logs -n payment -l app=payment-service --tail=20
```

---

## 💡 Step 3: Resolve the Mismatch

Choose one of the two methods to align the ports.

### Option A: Edit the ServiceMonitor to target the working port (Recommended)
Update the ServiceMonitor endpoint to use the correct working port name (`prometheus`):

```bash
kubectl patch servicemonitor payment-service-monitor -n payment --type='json' \
  -p='[{"op": "replace", "path": "/spec/endpoints/0/port", "value": "prometheus"}]'
```

---

### Option B: Edit the Service to map the "metrics" port to the working containerPort (8080)
If you want to keep the ServiceMonitor pointing to `port: metrics`, update the service configuration so that `port: metrics` targets containerPort `8080` instead of `9090`:

```bash
kubectl patch svc payment-service -n payment --type='json' \
  -p='[{"op": "replace", "path": "/spec/ports/1/targetPort", "value": 8080}]'
```

---

## 🧹 Step 4: Cleanup

Tear down the lab components:
```bash
kubectl delete namespace payment
# Optional: uninstall monitoring stack if no longer needed
helm uninstall kube-prometheus-stack -n monitoring
kubectl delete namespace monitoring
```
