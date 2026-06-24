# Exercise 25: Observability Platform Deployment

This exercise demonstrates the deployment of a modern, production-grade observability platform in an EKS cluster. We deploy:
* **Prometheus**: For metrics scraping and storage.
* **Grafana Loki**: For high-performance log aggregation.
* **Grafana Tempo**: For distributed tracing.
* **Grafana Alloy**: The unified collector replacing Grafana Agent, configured to scrape metrics, tail logs, and receive OTLP traces.
* **Grafana**: Visualizing logs, metrics, and traces through unified dashboards.

---

## Folder Structure

```text
Exercise-25/
├── README.md
├── architecture-diagram.md
├── manifests/
│   ├── namespace.yaml
│   ├── alloy-config.yaml
│   └── grafana-dashboards/
│       ├── dashboards.yaml
│       ├── cpu-dashboard.json
│       ├── memory-dashboard.json
│       ├── error-rate-dashboard.json
│       └── request-rate-dashboard.json
├── helm/
│   ├── loki-values.yaml
│   ├── tempo-values.yaml
│   ├── prometheus-values.yaml
│   └── grafana-values.yaml
└── scripts/
    ├── deploy-observability.sh
    └── validation/
        └── verify-observability.sh
```

---

## Deployment Steps

### Step 1: Execute Automated Deployment Script
The deployment script adds required Helm charts, applies the custom Grafana Alloy configuration pipeline, applies the dashboard configmaps, and provisions the servers:
```bash
./scripts/deploy-observability.sh
```
Wait for all components to transition to `Running` state:
```bash
kubectl get pods -n observability -w
```

### Step 2: Retrieve Grafana Login Credentials
Fetch the auto-generated admin password:
```bash
kubectl get secret --namespace observability grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
```

### Step 3: Access Grafana Dashboard
Port-forward Grafana to access it locally on `http://localhost:3000`:
```bash
kubectl port-forward svc/grafana 3000:80 -n observability
```
Open your browser to `http://localhost:3000` (User: `admin` / Password retrieved in Step 2).

---

## Pre-provisioned Dashboards
Grafana is pre-configured to load four custom dashboards from Kubernetes ConfigMaps automatically:
1. **CPU Dashboard**: Displays pod CPU utilization rates.
2. **Memory Dashboard**: Displays pod memory working set sizes.
3. **Error Rate Dashboard**: Shows HTTP 5xx responses over time.
4. **Request Rate Dashboard**: Monitors request throughput (requests/sec).

To find them in Grafana:
* Go to **Dashboards** in the left menu.
* You will see the dashboards listed under the General folder.

---

## OpenTelemetry Application Instrumentation Guidance

To send metrics, logs, and traces from your applications to this observability stack:

### 1. Configure OpenTelemetry SDK in Python
Install dependencies:
```bash
pip install opentelemetry-api opentelemetry-sdk opentelemetry-exporter-otlp
```

Add the following initialization code to your microservice:
```python
import os
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource

# 1. Initialize Tracer Provider with Resource attributes
resource = Resource(attributes={
    "service.name": "customer-service",
    "service.version": "1.0.0",
    "deployment.environment": "production"
})

provider = TracerProvider(resource=resource)

# 2. Configure OTLP gRPC Exporter targeting Grafana Alloy collector
# Alloy runs in 'observability' namespace, listening on port 4317
otlp_endpoint = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", "alloy.observability.svc.cluster.local:4317")
otlp_exporter = OTLPSpanExporter(endpoint=otlp_endpoint, insecure=True)

# 3. Add processor
provider.add_span_processor(BatchSpanProcessor(otlp_exporter))
trace.set_tracer_provider(provider)

tracer = trace.get_tracer(__name__)

# Usage Example:
with tracer.start_as_current_span("read-database"):
    # Perform DynamoDB CRUD operations...
    pass
```

### 2. Configure Pod Environment Variables
Configure the OTel environment variables in your Kubernetes Deployment manifest:
```yaml
env:
- name: OTEL_EXPORTER_OTLP_ENDPOINT
  value: "http://alloy.observability.svc.cluster.local:4318" # OTLP HTTP
- name: OTEL_SERVICE_NAME
  value: "customer-app"
```

---

## Verification & Testing

Run the validation script to verify that Prometheus, Loki, and Grafana API endpoints are responsive:
```bash
./validation/verify-observability.sh
```

### Querying Logs in Grafana
* In Grafana, navigate to **Explore**.
* Select **Loki** from the datasource dropdown.
* In the label browser, search for `{filename="/var/log/pods/..."}` or `{kubernetes_namespace="observability"}`.
* Click **Run Query** to view live streaming logs.

### Querying Traces in Grafana
* Select **Tempo** from the datasource dropdown in **Explore**.
* Choose **Search** tab.
* Hit **Run Query** to view spans and transaction latency graphs. You can drill down to see trace timelines.

---

## Production Best Practices

1. **Persistent Storage Backends**:
   In production, do not store Loki chunks or Tempo block files on local EBS volumes. Configure object storage backends like **Amazon S3** (using IRSA for permissions). This is highly durable and costs 90% less than EBS disks.
2. **Grafana High Availability**:
   Run Grafana with at least 2 replicas, and configure a shared PostgreSQL database (e.g. AWS RDS) to store session and dashboard states instead of the default SQLite local database.
3. **Loki Compactor**:
   Enable the Loki Compactor component to clean up old indices and enforce retention policies (e.g., automatically deleting log entries older than 14 days).

## Security Considerations
* **Authentication**: Enforce SSO (Single Sign-On) using OAuth/OIDC providers (e.g., Keycloak, Okta, or Google Workspace) in Grafana.
* **Network Isolation**: Restrict ports 3100 (Loki), 9090 (Prometheus), and 4317 (Alloy) within the cluster. Pods from outside the `observability` namespace should only be able to hit Alloy ingestion ports.

## Cost Considerations
* **Trace Sampling**: Tracing generates a large volume of data. Use **tail-based sampling** in Grafana Alloy to only retain trace traces that contain errors (HTTP 5xx) or exceed a latency threshold (e.g., > 1s), dropping successful traces to save storage costs.
* **Log Retention**: Restrict Loki log retention. In dev environments, limit retention to 3 days, and production to 14 days.

---

## Troubleshooting Guide

### 1. Grafana Datasource fails to connect
* Verify service names and namespaces: `kubectl get svc -A`. The URL must match the internal Kubernetes cluster domain, e.g. `http://loki.observability.svc.cluster.local:3100`.
* Check if pods are running: `kubectl get pods -n observability`.

### 2. Alloy collector logs show "Connection Refused" when pushing
* Ensure Loki and Tempo services are active and listening.
* Check Loki pod logs: `kubectl logs -n observability -l app.kubernetes.io/name=loki`.
* Ensure that the Alloy config file correctly points to the active port endpoints.

---

## Cleanup
To destroy the observability platform:
```bash
helm uninstall grafana -n observability
helm uninstall tempo -n observability
helm uninstall loki -n observability
helm uninstall prometheus-server -n observability
helm uninstall alloy -n observability
kubectl delete -f manifests/grafana-dashboards/dashboards.yaml
kubectl delete -f manifests/alloy-config.yaml
kubectl delete -f manifests/namespace.yaml
```
