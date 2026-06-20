# Exercise 18: GitOps Multi-Environment Deployment with ArgoCD and Helm

## Objective
Implement GitOps pipelines using **ArgoCD** and **Helm** on a Kubernetes cluster. 
This project sets up three environments (`dev`, `qa`, and `prod`) running a custom Python web application.

Features demonstrated:
* **Declarative Multi-Environment Setup**: One shared Helm chart configured dynamically using environment-specific values files.
* **Auto-Sync**: Automatically synchronizes state from Git to the Kubernetes cluster on every commit/push.
* **Self-Healing**: Automatically corrects manually introduced cluster drifts (e.g. manually deleted deployments).
* **Pruning**: Automatically deletes Kubernetes resources from the cluster when they are removed from Git.

---

## Architecture

```text
       Developer
           │
      git commit/push
           │
           ▼
     GitHub Repository (Source of Truth)
           │
           ├────────────────────────────┬────────────────────────────┐
           ▼                            ▼                            ▼
     [ArgoCD Application]         [ArgoCD Application]         [ArgoCD Application]
       python-app-dev               python-app-qa                python-app-prod
           │                            │                            │
      watches repo                 watches repo                 watches repo
   gitops/dev/values.yaml       gitops/qa/values.yaml        gitops/prod/values.yaml
           │                            │                            │
           ▼                            ▼                            ▼
    Namespace: dev               Namespace: qa                Namespace: prod
    Replicas: 1                  Replicas: 2                  Replicas: 3
```

---

## Directory Structure

```text
Exercise-18/
├── README.md                 # Detailed instructions (this file)
├── app/
│   ├── Dockerfile            # Python application container configuration
│   └── app.py                # Visual HTTP web server (standard library)
├── helm-chart/
│   ├── Chart.yaml            # Helm chart metadata
│   ├── values.yaml           # Default values
│   └── templates/
│       ├── deployment.yaml   # Pod template injecting environment variables
│       └── service.yaml      # Service interface for the environment
├── gitops/
│   ├── dev/
│   │   └── values.yaml       # Dev environment values (1 replica)
│   ├── qa/
│   │   └── values.yaml       # QA environment values (2 replicas)
│   └── prod/
│       └── values.yaml       # Prod environment values (3 replicas)
└── argocd/
    ├── dev-app.yaml          # ArgoCD Application deploying to dev
    ├── qa-app.yaml           # ArgoCD Application deploying to qa
    └── prod-app.yaml         # ArgoCD Application deploying to prod
```

---

## Step-by-Step Setup & Verification

### 1. Build and Load Docker Image
For verification on a local Minikube cluster, build the Docker container and load it directly into Minikube's image registry:
```bash
# Build the image locally
docker build -t devops-python-app:v1 Exercise-18/app

# Load the image into Minikube
minikube image load devops-python-app:v1
```

> [!NOTE]
> **Production EKS Deployment**: If deploying to AWS EKS, push the image to AWS ECR instead, and update `repository` under `image` in `Exercise-18/helm-chart/values.yaml` to point to your ECR registry URL.

### 2. Apply ArgoCD Applications
Apply the declarations to register the three pipelines within ArgoCD:
```bash
kubectl apply -f Exercise-18/argocd/
```

### 3. Verify Syncing Status
Watch ArgoCD automatically create the namespaces and deploy the pods:
```bash
# Verify applications are Synced
kubectl get applications -n argocd

# Verify namespaces are created and pods are healthy
kubectl get pods -n dev
kubectl get pods -n qa
kubectl get pods -n prod
```
Expected output:
* `dev`: 1 pod
* `qa`: 2 pods
* `prod`: 3 pods

### 4. Query the Web Interfaces
Run a Python request one-liner inside the container network to view the environment-specific visual HTML outputs:
```bash
# Dev environment
kubectl exec -n dev deploy/python-app-dev-deployment -- python -c "import urllib.request; print(urllib.request.urlopen('http://localhost:8080').read().decode('utf-8'))"

# QA environment
kubectl exec -n qa deploy/python-app-qa-deployment -- python -c "import urllib.request; print(urllib.request.urlopen('http://localhost:8080').read().decode('utf-8'))"

# Prod environment
kubectl exec -n prod deploy/python-app-prod-deployment -- python -c "import urllib.request; print(urllib.request.urlopen('http://localhost:8080').read().decode('utf-8'))"
```

---

## Demonstrating GitOps Strengths

### Demo 1: Self-Healing
Delete the Deployment resource manually using the Kubernetes CLI:
```bash
kubectl delete deployment python-app-dev-deployment -n dev
```
Immediately verify it has been deleted:
```bash
kubectl get deployment -n dev
```
Wait `15-30` seconds. ArgoCD will automatically detect the drift and reconstruct the Deployment resource to match the Git state:
```bash
kubectl get deployment -n dev
```

### Demo 2: Pruning
Prune service resources by removing the template from Git:
```bash
# Remove service from local git tracking
git rm Exercise-18/helm-chart/templates/service.yaml
git commit -m "Test pruning: remove service template"
git push origin main
```
Wait `15-30` seconds. Check service status to confirm ArgoCD has completely removed the Services from the cluster namespaces:
```bash
kubectl get service -n dev
kubectl get service -n qa
kubectl get service -n prod
```

Restore the service template to resume standard operations:
```bash
# Restore local file
git checkout origin/main -- Exercise-18/helm-chart/templates/service.yaml
git add Exercise-18/helm-chart/templates/service.yaml
git commit -m "Restore service template"
git push origin main
```
Confirm the service returns automatically:
```bash
kubectl get service -n dev
```

---

## ArgoCD Troubleshooting

### Fixing applicationset-controller CrashLoopBackOff
If the ApplicationSet controller pod in the `argocd` namespace is in `CrashLoopBackOff`, it is due to missing ApplicationSet CRDs. Fix it by applying the CRD definition directly:
```bash
kubectl apply -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.11.3/manifests/crds/applicationset-crd.yaml
kubectl delete pod -n argocd -l app.kubernetes.io/name=argocd-applicationset-controller
```
