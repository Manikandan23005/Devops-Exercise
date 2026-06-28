# Exercise 13 – Secret Rotation Outage Investigation

## 📋 Incident Overview
Following a secret rotation in the external Secret Manager (e.g. AWS Secrets Manager or HashiCorp Vault), client requests start failing with **`401 Unauthorized`**.
* **Application Logs**: `Token validation failed`
* **Kubernetes Secret Status**: `kubectl get secret payment-secret` reveals `Last Updated: 2 weeks ago` (un-rotated).

---

## 🛠️ Step 1: Lab Setup (Create Scenario)

Run the following commands to configure and trigger the simulation in your local cluster:

### 1. Deploy the namespace, secret, and payment-service:
```bash
kubectl apply -f manifests/
```

### 2. Verify the application runs and has the old token loaded:
```bash
kubectl logs -n secret-outage -l app=payment-service
```

### 3. Trigger the 401 failure:
Simulate a client making a call with the newly rotated token (`new-rotated-token`):
```bash
kubectl run client-test -n secret-outage --rm -it --image=curlimages/curl --restart=Never -- \
  curl -i -X POST http://payment-service:8080/pay \
  -H "Authorization: Bearer new-rotated-token"
```
*Expected Output*: Returns `HTTP/1.1 401 Unauthorized` and prints `ERROR: Token validation failed` in the pod logs.

---

## 🔍 Step 2: Diagnostic Analysis (Why Secret Rotation Failed)

Based on the evidence that the Kubernetes Secret `payment-secret` was **Last Updated: 2 weeks ago**, the secret rotation did not propagate from the external provider to Kubernetes. Here is why:

### 1. External Secrets Operator (ESO) Sync Failure
In GitOps/Cloud-native architectures, secrets are synced using tools like the **External Secrets Operator (ESO)**. The failure points are:
* **`refreshInterval` is too high or set to `0`**: The `ExternalSecret` manifest defines how often to check the provider for updates. If `refreshInterval` is `0` or blank, auto-sync is disabled.
* **Authentication/Permissions expired**: The IAM role or ServiceAccount used by the `SecretStore` to talk to AWS Secrets Manager/Vault might have lost permissions, expired, or been changed.
* **ESO Operator Pod is down**: The controller daemonset/deployment itself might be down or crashlooping.
* **Invalid JSON structure**: If the rotated secret in the external store had its JSON schema changed (e.g. key renamed), the operator will fail to parse and update the target Kubernetes secret.

### 2. Application-Level Cache / Environment Variables
Even if the Kubernetes Secret *did* update, the application pod can still experience outages due to:
* **Environment Variables are Static**: If the secret is mounted via `valueFrom.secretKeyRef` (as environment variables), **Kubernetes does not update environment variables in running containers when the underlying Secret changes**. The pod must be restarted to load the new value.
* **No dynamic reload on Volume Mounts**: If the secret is mounted as a file volume, Kubernetes updates the mounted files eventually (up to 2 minutes), but the application code must actively watch and re-read the file on change. If the app reads the secret key *only once at startup*, it will use the stale token until the container is restarted.

---

## 🛠️ Step 3: Recovery Steps

### 1. Check the Status of the Sync Operator (ESO)
Verify that the External Secrets resources are configured correctly and healthy:
```bash
# Check if ExternalSecret is synced
kubectl get externalsecret payment-secret -n secret-outage -o yaml

# Describe the resource to check status events and errors
kubectl describe externalsecret payment-secret -n secret-outage
```

### 2. Verify Provider Authentication (SecretStore)
Check if the `SecretStore` is valid and authorized:
```bash
kubectl get secretstore -n secret-outage
kubectl describe secretstore -n secret-outage
```

### 3. Re-Sync the Secret Manually
Force a reconciliation to sync the rotated secret immediately:
```bash
# Using External Secrets CLI or patching the annotation to force reconciliation
kubectl annotate externalsecret payment-secret force-sync=$(date +%s) --overwrite -n secret-outage
```

### 4. Perform a Rolling Restart of the Application
Once the Kubernetes Secret is verified as updated, restart the pods to pick up the new environment variable value:
```bash
kubectl rollout restart deployment/payment-service -n secret-outage
```

---

## 🧹 Step 4: Cleanup

Tear down the simulation components:
```bash
kubectl delete namespace secret-outage
```
