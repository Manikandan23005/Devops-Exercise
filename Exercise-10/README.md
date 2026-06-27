# Exercise 10 – Loki Logging Failure

## Incident Overview

Logs have stopped appearing in Grafana. 
* **Alloy Logs** show: `failed to push logs` with status code **HTTP 403**.
* **Loki Logs** show: `authentication failed` or `tenant ID not found in request`.

---

## 🔍 Log Flow & Trace Analysis

To determine the failure point, trace the flow chronologically:

```text
+-----------------------+               +-----------------------+               +-----------------------+               +-----------------------+
|  1. Application Pod   |  Stdout Logs  |    2. Grafana Alloy   |   HTTP POST   |    3. Grafana Loki    |  Query logs   |      4. Grafana       |
| (Writes logs to disk) | ------------> | (Tails files, pushes) | ------------> |  (Ingests & Indexes)  | ------------> |      (Visualizes)     |
+-----------------------+               +-----------------------+               +-----------+-----------+               +-----------------------+
                                                                                            |
                                                                                            | Checks auth_enabled: true
                                                                                            v
                                                                                [HTTP 403 Forbidden Error]
                                                                                (X-Scope-OrgID header missing)
```

1. **Application:** Pod prints logs to `/var/log/pods` (via stdout). **[Status: Working]**
2. **Alloy:** Discovers pods, reads logs, and formats them. Fails when POSTing to Loki. **[Status: Failed at egress]**
3. **Loki:** Receives push requests, but since `auth_enabled: true` is configured, it requires a tenant ID in the headers (`X-Scope-OrgID`). Because the header is missing, Loki rejects the request. **[Status: Denying requests]**
4. **Grafana:** Displays "No Data" as Loki has no logs for that query. **[Status: No logs shown]**

---

## 🛠️ Step 1: Lab Setup (Create Scenario)

Run the following commands to configure and trigger the issue:

### 1. Create the `logging-lab` namespace
```bash
kubectl create namespace logging-lab
```

### 2. Add Grafana Helm repo and install Loki with authentication enabled
```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm upgrade --install loki grafana/loki \
  --namespace logging-lab \
  -f manifests/loki-values.yaml
```

### 3. Deploy the Alloy ConfigMap and Alloy Collector
```bash
# Apply ConfigMap
kubectl apply -f manifests/alloy-config.yaml

# Install Alloy
helm upgrade --install alloy grafana/alloy \
  --namespace logging-lab \
  --set alloy.configMap.name=alloy-config \
  --set alloy.configMap.key=config.alloy
```

### 4. Deploy the Log Generator Application
```bash
kubectl apply -f manifests/log-generator.yaml
```

---

## 🔍 Step 2: Troubleshooting (Find Failure Point)

Run these queries to identify why the flow is broken.

### 1. Verify Application Logs (Step 1 of Flow)
Verify the application is writing logs to stdout:
```bash
kubectl logs -n logging-lab -l app=log-generator --tail=10
```
*Expected Output:* Shows transaction logs printing successfully.

### 2. Check Alloy logs for push errors (Step 2 of Flow)
Check Alloy logs to see if egress forwarding works:
```bash
kubectl logs -n logging-lab -l app.kubernetes.io/name=alloy --tail=30
```
*Expected Output:*
```text
failed to push logs ... status code 403
```

### 3. Check Loki logs for authentication failure (Step 3 of Flow)
Check Loki container logs to see why it returned a 403:
```bash
kubectl logs -n logging-lab -l app.kubernetes.io/name=loki --tail=30
```
*Expected Output:*
```text
level=warn msg="authentication failed: tenant ID not found in request"
```

---

## 💡 Step 3: Resolve the Issue

Choose one of the two resolution paths.

### Option A: Disable Multi-Tenant Authentication in Loki (Easiest)
If multi-tenancy is not needed, disable `auth_enabled` in Loki's configuration:

```bash
# Upgrade Loki with auth_enabled=false
helm upgrade loki grafana/loki \
  --namespace logging-lab \
  --set loki.auth_enabled=false
```

---

### Option B: Inject the Tenant ID in Alloy's Configuration (Production Best Practice)
To support multi-tenancy securely, configure Alloy to add the required `tenant_id` to its Loki egress endpoint.

1. Run the following command to patch the ConfigMap with `tenant_id = "logging-lab"`:
```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: alloy-config
  namespace: logging-lab
data:
  config.alloy: |
    loki.write "local" {
      endpoint {
        url = "http://loki.logging-lab.svc.cluster.local:3100/loki/api/v1/push"
        tenant_id = "logging-lab" // Injects X-Scope-OrgID header
      }
    }

    discovery.kubernetes "pods" {
      role = "pod"
    }

    local.file_match "pod_logs" {
      path_targets = discovery.kubernetes.pods.targets
    }

    loki.source.file "pod_logs" {
      targets    = local.file_match.pod_logs.targets
      forward_to = [loki.write.local.receiver]
    }
EOF
```

2. Restart the Alloy pods to apply the new ConfigMap:
```bash
kubectl rollout restart daemonset/alloy -n logging-lab
```

3. Verify that logs are now being pushed successfully without 403 errors:
```bash
kubectl logs -n logging-lab -l app.kubernetes.io/name=alloy --tail=10
```

---

## 🧹 Step 4: Cleanup

Tear down the lab components:
```bash
kubectl delete namespace logging-lab
```
