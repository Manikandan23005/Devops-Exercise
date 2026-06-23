# Exercise-01: EKS Application Deployment via GitOps

## Architecture

```text
Developer
    │  git push
    ▼
GitHub Repository (github.com/company/payment-service)
    │  GitHub Actions CI/CD
    ▼
Amazon ECR  (028987315631.dkr.ecr.ap-south-1.amazonaws.com/payment-service)
    │  image tag written back to helm/values.yaml
    ▼
ArgoCD  (auto-sync + self-heal + prune)
    │
    ▼
EKS Cluster  (production-eks  ·  ap-south-1)
    ├── payment-service  (Deployment · 2 replicas)
    ├── AWS Secrets Manager  ←  External Secrets Operator
    ├── IRSA  (payment-service-irsa-role)
    ├── ALB Ingress  (payment.company.internal)
    └── Prometheus → Grafana
```

---

## Learning Objectives

After completing this exercise you will understand:

* How to build a production GitOps pipeline with GitHub Actions, ECR, ArgoCD, and EKS
* IRSA (IAM Roles for Service Accounts) for fine-grained pod-level AWS access
* External Secrets Operator — syncing AWS Secrets Manager values into Kubernetes Secrets
* AWS Load Balancer Controller — ALB-backed Ingress for EKS workloads
* Prometheus ServiceMonitor and Grafana dashboards for observability
* Helm chart structure for a production microservice

---

## Environment Setup

| Component | Value |
|---|---|
| EKS Cluster | `production-eks` (ap-south-1) |
| Node Group Role | `eks-nodegroup-role` |
| ECR Repository | `payment-service` |
| AWS Secret | `payment-service-secret` |
| IRSA Role | `payment-service-irsa-role` |
| Kubernetes Namespace | `payment` |
| ServiceAccount | `payment-service-sa` |
| Deployment | `payment-service` |
| Ingress Host | `payment.company.internal` |

### Directory Structure

```text
Exercise-1/
├── README.md
├── terraform/
│   └── main.tf                          ← AWS infrastructure (EKS, ECR, IRSA, Secrets Manager)
├── app/
│   ├── app.py                           ← Python Flask microservice
│   ├── requirements.txt
│   ├── Dockerfile
│   └── tests/
│       └── test_app.py                  ← Unit tests
├── helm/
│   └── payment-service/
│       ├── Chart.yaml
│       ├── values.yaml                  ← image.tag updated by CI/CD
│       └── templates/
│           ├── _helpers.tpl
│           ├── deployment.yaml
│           ├── service.yaml
│           ├── ingress.yaml
│           ├── serviceaccount.yaml
│           └── servicemonitor.yaml
├── hands-on/
│   ├── namespace.yaml
│   ├── serviceaccount.yaml              ← IRSA annotation
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml                     ← ALB Ingress
│   ├── secretstore.yaml                 ← External Secrets SecretStore
│   ├── externalsecret.yaml              ← External Secrets ExternalSecret
│   ├── servicemonitor.yaml              ← Prometheus scrape config
│   └── argocd-application.yaml         ← ArgoCD Application (auto-sync)
├── monitoring/
│   └── grafana-dashboard.json           ← Payment Service Health dashboard
└── .github/
    └── workflows/
        └── ci-cd.yaml                   ← GitHub Actions pipeline
```

---

## Section 1: AWS Infrastructure

Provision with Terraform:

```bash
cd terraform
terraform init
terraform plan
terraform apply -auto-approve
```

Resources created:

* EKS cluster `production-eks`
* Managed node group (`eks-nodegroup-role`)
* ECR repository `payment-service`
* AWS Secrets Manager secret `payment-service-secret`
* OIDC Provider for IRSA
* IAM Role `payment-service-irsa-role` (scoped to `secretsmanager:GetSecretValue` on the secret)
* IAM Role `aws-load-balancer-controller-irsa-role`

---

## Section 2: Application — payment-service

Python Flask microservice with three endpoints:

| Endpoint | Response |
|---|---|
| `GET /` | `{"service":"payment-service","status":"healthy"}` |
| `GET /metrics` | Prometheus metrics (text/plain) |
| `GET /secret-check` | Verifies Secrets Manager access via IRSA |

Docker image:

```
028987315631.dkr.ecr.ap-south-1.amazonaws.com/payment-service:v1
```

---

## Section 3: Helm Chart

Structure follows the spec exactly:

```text
helm/payment-service/
├── Chart.yaml
├── values.yaml
└── templates/
    ├── deployment.yaml
    ├── service.yaml
    ├── ingress.yaml
    ├── serviceaccount.yaml
    └── servicemonitor.yaml
```

Deploy manually:

```bash
helm upgrade --install payment-service ./helm/payment-service \
  --namespace payment \
  --create-namespace
```

Verify:

```bash
helm list -n payment
helm status payment-service -n payment
```

---

## Section 4: IRSA

### How It Works

```text
Pod (payment-service)
  ↓  uses ServiceAccount: payment-service-sa
EKS Pod Identity Webhook
  ↓  injects AWS_ROLE_ARN + AWS_WEB_IDENTITY_TOKEN_FILE
AWS STS AssumeRoleWithWebIdentity
  ↓  returns temporary credentials
payment-service-irsa-role
  ↓  grants secretsmanager:GetSecretValue on payment-service-secret only
AWS Secrets Manager ✓
```

### Configure ServiceAccount

```bash
kubectl apply -f hands-on/serviceaccount.yaml
```

Verify annotation:

```bash
kubectl get sa payment-service-sa -n payment -o yaml
```

Expected:

```yaml
metadata:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::028987315631:role/payment-service-irsa-role
```

Verify IRSA environment variables inside the pod:

```bash
kubectl exec -it deployment/payment-service -n payment -- env | grep AWS
```

Expected:

```text
AWS_ROLE_ARN=arn:aws:iam::028987315631:role/payment-service-irsa-role
AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/secrets/eks.amazonaws.com/serviceaccount/token
```

---

## Section 5: External Secrets Operator

### Install

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets \
  --create-namespace
```

### Apply SecretStore and ExternalSecret

```bash
kubectl apply -f hands-on/secretstore.yaml
kubectl apply -f hands-on/externalsecret.yaml
```

### Verify

```bash
kubectl get secretstore -n payment
kubectl get externalsecret -n payment
kubectl get secret payment-secret -n payment
```

Expected ExternalSecret status:

```text
NAME                       STORE             REFRESH INTERVAL   STATUS   READY
payment-external-secret    aws-secret-store  1h                 SecretSynced   True
```

Verify the secret contains the correct keys:

```bash
kubectl get secret payment-secret -n payment -o jsonpath='{.data}' | jq 'keys'
```

Expected:

```json
["DB_HOST", "DB_PASSWORD", "DB_USER"]
```

---

## Section 6: ALB Ingress

### Install AWS Load Balancer Controller

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=production-eks \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::028987315631:role/aws-load-balancer-controller-irsa-role
```

### Apply Ingress

```bash
kubectl apply -f hands-on/ingress.yaml
```

### Verify

```bash
kubectl get ingress -n payment
```

Expected:

```text
NAME              CLASS   HOSTS                       ADDRESS                          PORTS   AGE
payment-service   alb     payment.company.internal    k8s-payment-xxxx.ap-south-1...   80      2m
```

Test the ALB endpoint:

```bash
ALB_DNS=$(kubectl get ingress payment-service -n payment -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -H "Host: payment.company.internal" http://$ALB_DNS/
```

Expected:

```json
{"service":"payment-service","status":"healthy"}
```

---

## Section 7: Observability

### Install Prometheus & Grafana

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --create-namespace \
  --set grafana.adminPassword=admin
```

### Apply ServiceMonitor

```bash
kubectl apply -f hands-on/servicemonitor.yaml
```

### Verify Prometheus scraping

```bash
kubectl get servicemonitor -n payment
```

Port-forward Prometheus and open the targets UI:

```bash
kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090
```

Open: http://localhost:9090/targets

Confirm `payment/payment-service` target is `UP`.

### Import Grafana Dashboard

```bash
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80
```

Open: http://localhost:3000 (admin / admin)

Import `monitoring/grafana-dashboard.json` — **Payment Service Health** dashboard shows:

| Panel | Query |
|---|---|
| Request Rate | `rate(payment_service_requests_total[5m])` |
| Error Rate | `rate(payment_service_errors_total[5m]) / rate(payment_service_requests_total[5m]) * 100` |
| P95 Latency | `histogram_quantile(0.95, rate(payment_service_request_latency_seconds_bucket[5m])) * 1000` |

---

## Section 8: GitHub Actions CI/CD

Workflow file: `.github/workflows/ci-cd.yaml`

### Pipeline Steps

```text
1. Run unit tests (pytest)
         ↓
2. Build Docker image  (tag = git SHA)
         ↓
3. Push to Amazon ECR
         ↓
4. Update helm/payment-service/values.yaml
         image.tag: <git-sha>
         ↓
5. git commit + push  [triggers ArgoCD]
```

### Secrets Required in GitHub Repository

| Secret | Description |
|---|---|
| `AWS_ROLE_TO_ASSUME` | IAM Role ARN for GitHub Actions OIDC |

Trigger the pipeline:

```bash
git commit -m "feat: update payment-service"
git push origin main
```

---

## Section 9: ArgoCD

### Install ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### Login

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443

argocd login localhost:8080 \
  --username admin \
  --password $(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d)
```

### Create Application

```bash
kubectl apply -f hands-on/argocd-application.yaml
```

Or via CLI:

```bash
argocd app create payment-service \
  --repo https://github.com/company/payment-service.git \
  --path helm/payment-service \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace payment \
  --sync-policy automated \
  --auto-prune \
  --self-heal
```

### Verify

```bash
argocd app list
argocd app get payment-service
```

Expected:

```text
Name:               payment-service
Sync Status:        Synced
Health Status:      Healthy
```

---

## Section 10: Deployment Flow

End-to-end deployment after a developer push:

```text
Developer push → main
     ↓
GitHub Actions triggered
     ↓
pytest unit tests pass
     ↓
docker build  (tag = abc1234)
     ↓
docker push  → ECR  (payment-service:abc1234)
     ↓
sed updates helm/values.yaml  image.tag: abc1234
     ↓
git commit & push  [skip ci]
     ↓
ArgoCD polls / webhook detects change
     ↓
ArgoCD auto-sync
     ↓
EKS: kubectl apply (rolling update)
     ↓
ALB routes traffic to new pods
     ↓
Prometheus scrapes /metrics
     ↓
Grafana dashboard updated
```

---

## Section 11: Validation Checklist

Run all of the following. Every resource must be in a healthy / ready state.

### Kubernetes Resources

```bash
# Pods – 2/2 Running
kubectl get pods -n payment

# Ingress – ALB address populated
kubectl get ingress -n payment

# ExternalSecret – SecretSynced: True
kubectl get externalsecret -n payment

# SecretStore – Valid
kubectl get secretstore -n payment

# ServiceAccount – annotation present
kubectl get serviceaccount payment-service-sa -n payment -o yaml

# ServiceMonitor – exists
kubectl get servicemonitor -n payment

# ArgoCD Application – Synced + Healthy
kubectl get applications -n argocd
```

### IRSA Verification

```bash
kubectl exec -it deployment/payment-service -n payment -- env | grep AWS
# Must show AWS_ROLE_ARN and AWS_WEB_IDENTITY_TOKEN_FILE

curl -H "Host: payment.company.internal" http://$ALB_DNS/secret-check
# {"status":"ok","db_host":"payment-db.internal"}
```

### Metrics in Prometheus

```bash
kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090
# Open http://localhost:9090 → query: payment_service_requests_total
```

### ALB Traffic

```bash
curl -H "Host: payment.company.internal" http://$ALB_DNS/
# {"service":"payment-service","status":"healthy"}
```

### ArgoCD Health

```bash
argocd app get payment-service
# Sync Status:   Synced
# Health Status: Healthy
```

---

## Commands Reference

```bash
# Infrastructure
terraform init && terraform apply -auto-approve

# Deploy manually (without ArgoCD)
kubectl apply -f hands-on/

# Helm
helm upgrade --install payment-service ./helm/payment-service -n payment --create-namespace

# ArgoCD
argocd app list
argocd app get payment-service
argocd app sync payment-service
argocd app diff payment-service
argocd app history payment-service

# Secrets
kubectl get secretstore -n payment
kubectl get externalsecret -n payment
kubectl get secret payment-secret -n payment

# Observability
kubectl get servicemonitor -n payment
kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80

# Logs
kubectl logs -n payment deployment/payment-service -f

# IRSA check
kubectl exec -it deployment/payment-service -n payment -- env | grep AWS
```
