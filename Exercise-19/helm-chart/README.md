# Python Application Helm Chart (Exercise 19)

A complete, production-grade Helm Chart designed to orchestrate and deploy a Python Flask application across multiple environments (`dev`, `qa`, and `prod`) on Kubernetes. 

This chart implements strict security contexts, network policies, horizontal pod autoscaling, high availability via pod disruption budgets, and follows modern cloud-native Kubernetes standards.

---

## 📂 Directory Structure

```text
helm-chart/
├── Chart.yaml              # Chart metadata, application version, and API version (v2)
├── values.yaml              # Default configuration values for all environments
├── values-dev.yaml          # Development environment overrides (1 replica, low resources)
├── values-qa.yaml           # QA environment overrides (2 replicas, HPA enabled, testing values)
├── values-prod.yaml         # Production environment overrides (3 replicas, high-availability, strict PDB)
├── charts/                  # Subcharts folder (empty, placeholder for dependencies)
├── templates/               # Kubernetes resource manifest templates
│   ├── _helpers.tpl         # Reusable template definitions (labels, naming, helper functions)
│   ├── deployment.yaml      # Deployment resource (Flask app, probes, securityContext, dynamic envs)
│   ├── service.yaml         # Service resource exposing the app (ClusterIP/NodePort)
│   ├── ingress.yaml         # Ingress resource for external access configurations
│   ├── configmap.yaml       # ConfigMap containing key-value environment pairs
│   ├── secret.yaml          # Encrypted sensitive credentials and API tokens
│   ├── hpa.yaml             # HorizontalPodAutoscaler scaling configurations
│   ├── pdb.yaml             # PodDisruptionBudget ensuring minimum available pods
│   ├── serviceaccount.yaml  # ServiceAccount mapping to pods
│   └── networkpolicy.yaml   # NetworkPolicy restricting container networking access
└── README.md                # This developer and operational guide
```

---

## 🛠️ Helm Engineering Concepts & Templating Features

This chart utilizes advanced Helm templating capabilities to ensure reusability and robustness:

| Concept / Feature | Purpose & Usage in This Chart |
| :--- | :--- |
| **`Chart.yaml`** | Metadata declarations containing Semantic Versioning (`version: 1.0.0`) and application versions (`appVersion: "1.0.0"`). |
| **`_helpers.tpl`** | Contains custom helper templates: `fullname`, `name`, `chart`, `labels`, `selectorLabels`, and `serviceAccountName`. |
| **`if` / `else`** | Used to conditionally deploy optional components (e.g., ingress, autoscaling, network policy, and pod disruption budgets). |
| **`range`** | Dynamically iterates over configurations like `configData`, `secretData`, ingress hosts, and path structures. |
| **`include`** | Injects inline helper definitions such as selector labels or standard labels. |
| **`define`** | Formulates reusable logic code blocks inside helper utilities. |
| **`tpl`** | Renders values as templates to allow dynamic evaluation inside variables (e.g. `{{ tpl $value $ }}`). |
| **`default`** | Asserts safe fallback parameters when values are omitted (e.g., tags, ports, and names). |
| **`required`** | Generates build-time errors if a critical value is missing (e.g., the container image repository name). |
| **`toYaml`** | Serializes complex nested objects (e.g. resources, node selectors, tolerations, and security contexts). |
| **`nindent`** | Correctly aligns serialized YAML blocks dynamically avoiding structure parsing errors. |

---

## 🌐 Environment Overrides & Configurations

This chart supports three distinct target environments with specific resource configurations:

### ⚙️ Parameters Matrix

| Environment | Replicas | CPU Request | Memory Request | Autoscaling | PDB |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **DEV** | `1` | `100m` | `128Mi` | Disabled | Disabled |
| **QA** | `2` | `250m` | `256Mi` | Enabled (`2`-`5` pods) | Enabled (`minAvailable: 1`) |
| **PROD** | `3` | `500m` | `512Mi` | Enabled (`3`-`10` pods) | Enabled (`minAvailable: 2`) |

---

## 🚀 Step-by-Step Operator Demonstration Guide

Use the following commands to validate, render, package, and manage releases.

### 1. Linting the Chart
Validate that the Helm chart adheres to standard syntaxes, structures, and best practices:
```bash
helm lint ./helm-chart
```

### 2. Dry-Run & Rendering Templates
Render the template manifests locally to confirm they resolve correctly before performing actual cluster writes:

* **Default Values Rendering:**
  ```bash
  helm template default-release ./helm-chart
  ```

* **DEV Environment Rendering:**
  ```bash
  helm template dev-release ./helm-chart -f ./helm-chart/values-dev.yaml
  ```

* **QA Environment Rendering:**
  ```bash
  helm template qa-release ./helm-chart -f ./helm-chart/values-qa.yaml
  ```

* **PROD Environment Rendering:**
  ```bash
  helm template prod-release ./helm-chart -f ./helm-chart/values-prod.yaml
  ```

### 3. Deploying to the Cluster (Install)
Install the chart to the target namespace (e.g. `dev`, `qa`, or `prod` environment):
```bash
# Example: Deploying to Dev
helm install dev-release ./helm-chart -f ./helm-chart/values-dev.yaml --namespace dev --create-namespace

# Example: Deploying to Prod
helm install prod-release ./helm-chart -f ./helm-chart/values-prod.yaml --namespace prod --create-namespace
```

### 4. Updating the Deployments (Upgrade)
Apply parameter or configuration changes to an active release:
```bash
helm upgrade dev-release ./helm-chart -f ./helm-chart/values-dev.yaml --namespace dev
```

### 5. Rolling Back a Deployment
Roll back to a previous revision if issues occur after upgrading:
```bash
# Check release status and list revisions
helm history dev-release --namespace dev

# Rollback release to Revision #1
helm rollback dev-release 1 --namespace dev
```

### 6. Packaging the Chart
Compile the Helm chart into a standardized, distributable archive (`.tgz` file) for registry publishing:
```bash
helm package ./helm-chart
```
*Generates file: `python-app-1.0.0.tgz`*

### 7. Uninstalling the Release
Cleanly remove all resources managed by the Helm release:
```bash
helm uninstall dev-release --namespace dev
```

---

## 🔍 Verification & Troubleshooting Guide

### 🛠️ Common Inspection Commands

1. **Verify Pod Status and Details:**
   ```bash
   kubectl get pods -n <namespace> -l app.kubernetes.io/name=python-app
   kubectl describe pod -n <namespace> -l app.kubernetes.io/name=python-app
   ```

2. **Check App Logs:**
   ```bash
   kubectl logs -n <namespace> -l app.kubernetes.io/name=python-app --tail=100
   ```

3. **Verify ConfigMaps & Secrets mount:**
   ```bash
   kubectl get configmap -n <namespace>
   kubectl get secret -n <namespace>
   ```

4. **Verify Networking and Services:**
   ```bash
   kubectl get svc -n <namespace>
   kubectl get ingress -n <namespace>
   ```

### 🚨 Common Errors and Resolution

* **`Error: values.yaml: image.repository: A valid image repository must be specified...`**
  * *Reason:* The `image.repository` field is marked as `required`.
  * *Fix:* Ensure `image.repository` has a valid repository name specified in `values.yaml` or provided via command line: `--set image.repository=my-repo`.

* **`CreateContainerConfigError`**
  * *Reason:* The referenced ConfigMap or Secret is missing or failed to generate.
  * *Fix:* Check if the ConfigMap/Secret generation is enabled, and make sure their names match the release name selector.

* **`CrashLoopBackOff` or failed Liveness/Readiness Probes**
  * *Reason:* The container could not start up, port configuration mismatch (`targetPort` != container listening port), or health check endpoint `/healthz` returned non-2xx status code.
  * *Fix:* Verify that the Python Flask application listens on the port configured in `values.yaml` under `service.targetPort` (default is `8080`) and exports a route at `/healthz`.
