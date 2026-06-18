# Exercise 3 – ArgoCD OutOfSync Production Incident

## Objective

Investigate why an ArgoCD Application is reporting `OutOfSync` in production, diagnose
the replica count drift between the Git-desired state and the live Kubernetes cluster,
and restore a healthy `Synced` status without downtime.

---

## Scenario

### Incident

The on-call engineer receives a PagerDuty alert at **03:14 UTC**:

```text
[CRITICAL] ArgoCD Application 'payment-service' is OutOfSync
Namespace    : production
Sync Status  : OutOfSync
Health Status: Degraded
Cluster      : prod-eks-cluster (ap-south-1)
```

The ArgoCD UI shows the application is **OutOfSync** — the live deployment replica count
has drifted from what is stored in Git.

### Observed Symptoms

| Signal | Value |
|---|---|
| ArgoCD Sync Status | `OutOfSync` |
| ArgoCD Health Status | `Degraded` |
| Git desired replicas | `5` |
| Live cluster replicas | `0` |
| Running pods | `0 / 5` |
| Last successful sync | `2026-06-18 22:00 UTC` |

### Timeline

```text
2026-06-18 22:00 UTC  ArgoCD synced commit def5678  →  replicas: 5  →  Healthy ✓
2026-06-19 02:45 UTC  Traffic spike, pods OOMKilled
2026-06-19 03:05 UTC  On-call engineer runs: kubectl scale deployment payment-service
                       --replicas=0  (intended to restart pods but forgot to scale back)
2026-06-19 03:14 UTC  ArgoCD detects drift  →  OutOfSync + Degraded alert fires
```

---

## Repository Structure

```text
Exercise-3/
├── README.md                        ← This file (incident report + runbook)
├── gitops/
│   ├── apps/
│   │   └── payment-service/
│   │       └── argocd-app.yaml      ← ArgoCD Application manifest
│   └── manifests/
│       └── payment-service/
│           ├── namespace.yaml       ← Namespace definition
│           ├── deployment.yaml      ← DESIRED state in Git  (replicas: 5)
│           ├── service.yaml         ← Service manifest
│           ├── configmap.yaml       ← ConfigMap with app config
│           └── hpa.yaml             ← HorizontalPodAutoscaler
└── broken-state/
    └── deployment-live.yaml         ← LIVE drifted state on cluster (replicas: 0)
```

---

## Architecture

```text
Developer
  ↓  git push
GitHub Repository  (desired state  →  replicas: 5)
  ↓  webhook / poll
ArgoCD
  ↓  compares
Live Kubernetes Cluster  (actual state  →  replicas: 0)
```

Expected GitOps Flow:

```text
Git (replicas: 5)
  ↓
ArgoCD detects no diff
  ↓
Status: Synced + Healthy  ✓
```

Actual Broken Flow:

```text
Git (replicas: 5)
  ↓
On-call engineer manually runs:
  kubectl scale deployment payment-service --replicas=0
  ↓
Live cluster  →  replicas: 0
  ↓
Git ≠ Cluster  →  ArgoCD reports OutOfSync + Degraded
```

---

## Investigation

### Step 1: Check ArgoCD Application Status

```bash
# List all ArgoCD applications
argocd app list
```

Expected output:

```text
NAME             CLUSTER    NAMESPACE   PROJECT     STATUS     HEALTH
payment-service  in-cluster production  production  OutOfSync  Degraded
```

```bash
# Get detailed status
argocd app get payment-service
```

Expected output:

```text
Name:               payment-service
Project:            production
Server:             https://kubernetes.default.svc
Namespace:          production
Repo:               https://github.com/myorg/gitops-repo
Target:             main
Path:               Exercise-3/gitops/manifests/payment-service

Sync Status:        OutOfSync
Health Status:      Degraded

GROUP  KIND        NAMESPACE   NAME             STATUS     HEALTH    MESSAGE
apps   Deployment  production  payment-service  OutOfSync  Degraded  Desired replicas: 5, actual: 0
```

---

### Step 2: View the Exact Diff

```bash
argocd app diff payment-service
```

Expected output:

```diff
===== apps/Deployment production/payment-service ======
spec:
-  replicas: 5    # Git (desired state)
+  replicas: 0    # Live cluster (drifted — manually scaled by on-call)
```

This single line tells the whole story: Git wants **5** replicas, the cluster has **0**.

---

### Step 3: Inspect the Live Deployment

```bash
# Check the live replica count directly
kubectl get deployment payment-service -n production
```

Expected output:

```text
NAME              READY   UP-TO-DATE   AVAILABLE   AGE
payment-service   0/0     0            0           18h
```

```bash
# Describe the deployment for full details
kubectl describe deployment payment-service -n production
```

Look for:

```text
Replicas:  0 desired | 0 updated | 0 total | 0 available | 0 unavailable
```

```bash
# Confirm zero pods are running
kubectl get pods -n production -l app=payment-service
```

Expected output:

```text
No resources found in production namespace.
```

---

### Step 4: Find Who Scaled the Deployment

```bash
# Check recent Kubernetes events in the namespace
kubectl get events -n production \
  --sort-by='.lastTimestamp' \
  --field-selector reason=ScalingReplicaSet
```

Expected output:

```text
LAST SEEN  TYPE    REASON               OBJECT                          MESSAGE
11m        Normal  ScalingReplicaSet    Deployment/payment-service      Scaled down replica set
                                                                        payment-service-7d9f to 0
```

```bash
# Check rollout history for the scale event
kubectl rollout history deployment/payment-service -n production
```

```text
REVISION  CHANGE-CAUSE
1         Initial deploy  (replicas: 5)
2         <none>          ← manual kubectl scale, no recorded reason
```

---

### Step 5: Check ArgoCD Sync History

```bash
argocd app history payment-service
```

Expected output:

```text
ID   DATE                           REVISION
4    2026-06-18 22:00:00 +0000 UTC  def5678  ← last successful sync (replicas: 5)
3    2026-06-18 18:00:00 +0000 UTC  ghi9012
```

ArgoCD has **not synced since 22:00** — the drift was caused by a manual `kubectl` command
after the last sync, not by a new Git commit.

---

## Root Cause Analysis (RCA)

### Evidence

| Finding | Detail |
|---|---|
| Git desired replicas | `5` (unchanged since commit `def5678`) |
| Live cluster replicas | `0` |
| Cause of drift | On-call engineer ran `kubectl scale deployment payment-service --replicas=0` at 03:05 UTC |
| Reason for manual scale | Intended to restart pods during OOMKilled incident |
| Why replicas stayed at 0 | Engineer forgot to scale back up after pods restarted |
| ArgoCD selfHeal | Disabled — did not auto-revert the manual change |

### Root Cause

The on-call engineer manually scaled the deployment to `0` using `kubectl` to stop
OOMKilled pods, intending to restart them. The engineer forgot to scale back to `5`.
Because ArgoCD `selfHeal` was **not enabled**, it detected the drift but did not
auto-correct it. The application was left with zero pods, causing `Degraded` health.

### Why ArgoCD Reported OutOfSync

ArgoCD polls the cluster every 3 minutes (default). At **03:14 UTC** it compared:

```text
Git  →  spec.replicas: 5
Live →  spec.replicas: 0
```

The difference was detected and the application was marked `OutOfSync`.

---

## Fix

### Option A: Git-First Sync (Recommended — GitOps Approach)

Since Git already has the correct value (`replicas: 5`), simply trigger ArgoCD to
re-sync. The cluster will be brought back in line with Git.

**Step 1 – Trigger a manual sync**

```bash
argocd app sync payment-service
```

ArgoCD applies the Git manifest, which sets `replicas: 5` on the cluster.

**Step 2 – Verify pods are coming up**

```bash
kubectl get pods -n production -l app=payment-service -w
```

Expected output (watch mode):

```text
NAME                               READY   STATUS              RESTARTS   AGE
payment-service-7d9f8b9c4-2xkpq   0/1     ContainerCreating   0          3s
payment-service-7d9f8b9c4-5nrtv   0/1     ContainerCreating   0          3s
payment-service-7d9f8b9c4-9qmpl   0/1     ContainerCreating   0          3s
payment-service-7d9f8b9c4-kbwzd   0/1     ContainerCreating   0          3s
payment-service-7d9f8b9c4-vlhsx   0/1     ContainerCreating   0          3s
payment-service-7d9f8b9c4-2xkpq   1/1     Running             0          12s
payment-service-7d9f8b9c4-5nrtv   1/1     Running             0          13s
...
```

---

### Option B: Emergency kubectl Scale (Break-Glass)

> ⚠️ Use only when ArgoCD is unavailable and immediate pod restoration is needed.
> This creates further drift — always follow up with Option A immediately after.

```bash
# Scale pods back to production count
kubectl scale deployment payment-service \
  --replicas=5 \
  -n production

# Watch pods recover
kubectl get pods -n production -l app=payment-service -w

# Then sync ArgoCD to reconcile Git and live state
argocd app sync payment-service
```

---

### Verify Recovery

```bash
# 1. Confirm ArgoCD shows Synced + Healthy
argocd app get payment-service
```

Expected:

```text
Sync Status:   Synced
Health Status: Healthy
```

```bash
# 2. Confirm 5 pods are running
kubectl get deployment payment-service -n production
```

Expected:

```text
NAME              READY   UP-TO-DATE   AVAILABLE   AGE
payment-service   5/5     5            5           18h
```

```bash
# 3. Confirm the spec.replicas value
kubectl get deployment payment-service -n production \
  -o=jsonpath='{.spec.replicas}'
```

Expected:

```text
5
```

---

## Key Concepts Learned

### What Is ArgoCD OutOfSync?

ArgoCD continuously compares the **desired state** (Git) with the **live state** (Kubernetes cluster).
When they differ, the application is marked `OutOfSync`.

```text
Git (source of truth)  ≠  Live Cluster  →  OutOfSync
Git (source of truth)  =  Live Cluster  →  Synced
```

---

### Why Is Manual `kubectl` Edit Dangerous in GitOps?

| Problem | Explanation |
|---|---|
| Creates drift | Git and cluster diverge silently |
| Overwritten on next sync | ArgoCD will undo the manual change at next sync |
| Confusion during incidents | "Is the cluster or Git correct?" |
| No audit trail | `kubectl scale` leaves no record in Git history |

**Rule**: In a GitOps workflow, the cluster state must **only** be changed via Git commits.

---

### ArgoCD selfHeal

If `selfHeal: true` is set in the ArgoCD Application, ArgoCD will **automatically revert**
any manual `kubectl` changes back to the Git-desired state within minutes.

```yaml
# argocd-app.yaml
syncPolicy:
  automated:
    selfHeal: true   # ← prevents this incident from happening
```

With selfHeal enabled:

```text
kubectl scale deployment payment-service --replicas=0
  ↓
ArgoCD detects drift (within 3 min)
  ↓
ArgoCD auto-syncs  →  replicas restored to 5
  ↓
Alert never fires  ✓
```

---

### ArgoCD Sync Policies

| Policy | Behaviour |
|---|---|
| `automated` | ArgoCD auto-syncs on every Git change |
| `automated + selfHeal` | Also auto-reverts manual `kubectl` changes |
| `none` (manual) | Operator must trigger sync manually |

> **Best Practice**: Enable `selfHeal: true` in production to prevent replica drift from
> manual interventions during incidents.

---

## Prevention Checklist

* [ ] Enable `selfHeal: true` in ArgoCD Application to auto-revert manual changes
* [ ] Configure ArgoCD notifications for Slack/PagerDuty on `OutOfSync`
* [ ] Document runbook: "Never use `kubectl scale` in production — use Git instead"
* [ ] Add `replicas` to the HPA so scaling is managed automatically, not manually
* [ ] Enable resource quota on the namespace to prevent accidental zero-replica scale
* [ ] Train on-call engineers on GitOps workflow for incident response

---

## Validation Checklist

* [ ] `argocd app get payment-service` shows `Synced` + `Healthy`
* [ ] `kubectl get deployment payment-service -n production` shows `5/5 READY`
* [ ] No pods in `Pending` or `CrashLoopBackOff` state
* [ ] Application health endpoint `/healthz/ready` returns `200 OK`
* [ ] ArgoCD `selfHeal` enabled to prevent future replica drift

---

## Commands Summary

```bash
# Inspect ArgoCD app status and diff
argocd app list
argocd app get payment-service
argocd app diff payment-service
argocd app history payment-service

# Sync Git desired state to cluster (restores replicas to 5)
argocd app sync payment-service

# Kubernetes investigation
kubectl get deployment payment-service -n production
kubectl get pods -n production -l app=payment-service
kubectl describe deployment payment-service -n production
kubectl get events -n production --sort-by='.lastTimestamp'
kubectl rollout history deployment/payment-service -n production

# Emergency break-glass (if ArgoCD unavailable)
kubectl scale deployment payment-service --replicas=5 -n production

# Verify replica count
kubectl get deployment payment-service -n production \
  -o=jsonpath='{.spec.replicas}'

# Enable selfHeal to prevent future drift
argocd app set payment-service \
  --sync-policy automated \
  --self-heal
```
