# Exercise 5 – Helm Upgrade Failure (spec.selector Immutability)

This folder contains a complete working lab to simulate the Helm upgrade failure caused by attempts to modify the immutable `spec.selector` field, and lists the exact commands to reproduce and resolve it.

## 📁 Lab Structure

```text
Exercise-5/
├── README.md                # Lab instructions (this file)
└── payment-service/         # The simulated Helm Chart
    ├── Chart.yaml
    ├── values.yaml
    └── templates/
        ├── deployment.yaml  # Configured to dynamically match selectorApp value
        └── service.yaml     # Routes traffic based on selectorApp value
```

---

## 🛠️ Step 1: Simulate the Error

Run the following commands in order to setup the deployment and trigger the error:

### 1. Create the dedicated namespace
```bash
kubectl create namespace exercise-5
```

### 2. Install Version 1 of the chart (using `selectorApp=payment`)
```bash
helm install payment-service ./payment-service \
  --set selectorApp=payment \
  --namespace exercise-5 \
  --wait
```

### 3. Verify Version 1 is running
```bash
kubectl get deployment payment-service -n exercise-5
```

### 4. Trigger the error by upgrading to Version 2 (using `selectorApp=payment-v2`)
```bash
helm upgrade payment-service ./payment-service \
  --set selectorApp=payment-v2 \
  --namespace exercise-5
```

**Expected Output:**
The upgrade command will fail with:
```text
Error: UPGRADE FAILED: cannot patch Deployment: spec.selector: Invalid value: field is immutable
```

---

## 💡 Step 2: Choose a Resolution Strategy

Use one of the following sets of commands to resolve the error.

### Option A: Manual Delete & Recreate (Brief Downtime)
Delete the deployment resource to clear the immutable selector constraint, then run the upgrade again:

```bash
# 1. Delete the active deployment resource
kubectl delete deployment payment-service -n exercise-5

# 2. Rerun the helm upgrade
helm upgrade payment-service ./payment-service \
  --set selectorApp=payment-v2 \
  --namespace exercise-5 \
  --wait
```

---

### Option B: Helm Force Upgrade (Brief Downtime)
Use Helm's built-in `--force` flag. This directs Helm to automatically delete and recreate the deployment resource when patching fails:

```bash
helm upgrade payment-service ./payment-service \
  --set selectorApp=payment-v2 \
  --force \
  --namespace exercise-5 \
  --wait
```

---

### Option C: Zero-Downtime Blue-Green Swap (Recommended for Production)
Perform a zero-downtime migration by deploying the new pods side-by-side, switching service routing, and then cleaning up:

```bash
# 1. Deploy the new deployment under a new name (payment-service-v2)
  cat <<EOF | kubectl apply -n exercise-5 -f -
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: payment-service-v2
    labels:
      app: payment-v2
  spec:
    replicas: 1
    selector:
      matchLabels:
        app: payment-v2
    template:
      metadata:
        labels:
          app: payment-v2
      spec:
        containers:
          - name: payment-service
            image: nginx:alpine
            ports:
              - name: http
                containerPort: 80
  EOF

# 2. Wait for the new pods to be ready
kubectl rollout status deployment/payment-service-v2 -n exercise-5

# 3. Patch the service selector to route traffic to payment-v2
kubectl patch svc payment-service -n exercise-5 --type='json' \
  -p='[{"op": "replace", "path": "/spec/selector/app", "value": "payment-v2"}]'

# 4. Delete the old deployment
kubectl delete deployment payment-service -n exercise-5
```

---

## 🧹 Step 3: Cleanup

Once you are done with the lab, clean up the namespace and resources by running:
```bash
kubectl delete namespace exercise-5
```
