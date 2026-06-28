# Exercise 14 – Distributed Tracing Investigation

## 📋 Incident Overview
Users are complaining that the `Checkout API` is slow.
* **Grafana Dashboard**: 95th percentile latency of the `checkout-service` is **4.8 seconds**.
* **Prometheus Metrics**: Request count is normal (no sudden traffic spikes).
* **Tempo Trace**: Tracing shows the request propagation path and duration:
  ```text
  checkout-service [4.8s]
  └── inventory-service [4.3s]
      └── payment-service [4.2s]
  ```

---

## 🛠️ Step 1: Lab Setup (Create Scenario)

Run the following commands to configure the microservices simulation in your local cluster:

### 1. Deploy the namespace and three microservices:
```bash
kubectl apply -f manifests/
```

### 2. Verify all pods are running:
```bash
kubectl get pods -n tracing-lab
```

### 3. Send a test checkout request:
Create a temporary pod to call the checkout endpoint:
```bash
kubectl run client-test -n tracing-lab --rm -it --image=curlimages/curl --restart=Never -- \
  curl -i -X POST http://checkout-service:8080/checkout
```
*Expected Output*: Returns `HTTP/1.1 200 OK` in approximately **4.8 seconds** showing:
```json
{
  "status": "success",
  "total_latency_seconds": 4.8,
  "details": {
    "inventory_status": "in_stock",
    "payment_details": {
      "payment_status": "authorized",
      "payment_latency": 4.2
    }
  }
}
```

---

## 🔍 Step 2: Investigation Workflow & Finding the Bottleneck

To find the bottleneck, we follow the **Three Pillars of Observability**: Metrics, Traces, and Logs.

```text
[Request]
   │
   ├──> checkout-service (Total: 4.8s, Local overhead: 0.5s)
   │       │
   │       └──> inventory-service (Total: 4.3s, Local overhead: 0.1s)
   │               │
   │               └──> payment-service (Total: 4.2s, Local overhead: 4.2s) <── [BOTTLENECK]
```

### 1. Analyze Traces (Tempo)
By loading the Trace ID in Grafana Tempo, we get a tree of spans corresponding to the call chain:
* `checkout-service` root span is active for 4.8s.
* `inventory-service` child span is active for 4.3s.
* `payment-service` leaf span is active for 4.2s.

**Conclusion**: Since `payment-service` accounts for `4.2s / 4.8s (87.5%)` of the total transaction time, it is the primary bottleneck. The upstream services (`checkout-service` and `inventory-service`) are simply blocked waiting for `payment-service` to respond.

### 2. Analyze Metrics (Prometheus)
* **Request Count**: Prometheus metrics show that the request count is normal (e.g. no DDoS or unexpected load spikes). This rules out generic connection pool saturation caused by traffic spikes.
* **Latency Histograms**: Comparing `http_request_duration_seconds_bucket` histograms across the three services confirms the high latency starts specifically inside the `payment-service` endpoints.

### 3. Correlate with Logs
By searching logs for `payment-service` matching the specific `trace_id`, we can pinpoint the root cause of the 4.2s delay:
* Run the following command to check logs on the simulation:
  ```bash
  kubectl logs -n tracing-lab -l app=payment-service
  ```
* **Simulated Root Causes Identified**:
  * `DEBUG: Slow SQL query: SELECT * FROM transaction_locks ...` (waiting for database lock acquisition).
  * `WARN: External gateway payment verification took 4.2 seconds (api.stripe.com)` (third-party dependency latency).

---

## 🛠️ Step 3: Resolution & Remediation

To resolve the 4.2s latency bottleneck in `payment-service`, we recommend:

1. **Optimize External Calls (Asynchronous / Webhooks)**:
   If the payment flow is synchronous, convert it to asynchronous. Accept the payment request, return a `202 Accepted` immediately, and use a Stripe webhook to update the transaction status.
2. **Database Optimization**:
   Add indexes to queried columns in the database, optimize transaction boundaries to minimize locks, or implement a read-replica/cache if querying static database data.
3. **HTTP Client Connection Pool Tuning**:
   Ensure connection reuse (Keep-Alive) is enabled for third-party API clients, and tune the connection pool size and timeouts (e.g. set a strict HTTP timeout of 2.0s so payment queries do not hang indefinitely).
4. **Scale Pods & Resources**:
   Ensure CPU/Memory limits of the `payment-service` pod are not throttling the application container:
   ```bash
   kubectl top pods -n tracing-lab
   ```

---

## 🧹 Step 4: Cleanup

Tear down the lab components:
```bash
kubectl delete namespace tracing-lab
```
