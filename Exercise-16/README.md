# Exercise 16: Production EKS Platform

## Objective
Build a production-ready EKS cluster using Terraform and Terragrunt.

**Components deployed:**
- EKS Cluster (Kubernetes v1.32)
- Managed Node Groups (t3.small, auto-scaling)
- Separate `dev` and `prod` namespaces
- Cluster Autoscaler (IRSA-enabled)
- Metrics Server

## Architecture

```
AWS (us-east-1)
└── VPC (10.0.0.0/16)
    ├── Public Subnets  → Internet Gateway + NAT Gateways
    └── Private Subnets → EKS Worker Nodes (t3.small)
                          EKS Control Plane (AWS Managed)
```

## Project Structure

```
Exercise-16/
├── terragrunt.hcl              # Root config (providers: AWS, K8s, Helm, TLS)
├── live/
│   ├── dev/terragrunt.hcl      # Dev: 2 nodes, t3.small, k8s 1.32
│   └── prod/terragrunt.hcl     # Prod: 3 nodes, t3.small, k8s 1.32
└── modules/eks-cluster/
    ├── main.tf                 # VPC, EKS, IAM, OIDC, namespaces, Helm releases
    ├── variables.tf            # Input variables
    ├── outputs.tf              # Cluster outputs
    └── versions.tf             # Required providers and backend
```

## Prerequisites

- AWS CLI v2 configured (`aws configure`)
- Terraform >= 1.0
- Terragrunt
- kubectl
- Helm >= 3.0

## Deploy

```bash
# 1. Configure AWS credentials
aws configure

# 2. Initialize providers
cd live/dev
terragrunt init --reconfigure

# 3. Deploy the cluster (~15-20 minutes)
terragrunt apply -auto-approve

# 4. Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name eks-dev-cluster
```

## Validation

```bash
# Check nodes are Ready
kubectl get nodes

# Check node CPU/memory metrics
kubectl top nodes

# Check namespaces
kubectl get ns
```

**Expected output — `kubectl get nodes`:**
```
NAME                          STATUS   ROLES    AGE   VERSION
ip-10-0-11-226.ec2.internal   Ready    <none>   5m    v1.32.13-eks-0de9cde
ip-10-0-12-140.ec2.internal   Ready    <none>   5m    v1.32.13-eks-0de9cde
```

**Expected output — `kubectl top nodes`:**
```
NAME                          CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
ip-10-0-11-226.ec2.internal   22m          1%       551Mi           38%
```

**Expected output — `kubectl get ns`:**
```
NAME              STATUS   AGE
default           Active
dev               Active       ← workloads go here
kube-node-lease   Active
kube-public       Active
kube-system       Active
prod              Active       ← workloads go here
```

## Check Add-ons

```bash
# Cluster Autoscaler
kubectl get pods -n kube-system | grep cluster-autoscaler

# Metrics Server
kubectl get pods -n kube-system | grep metrics-server
```

## Cleanup

```bash
cd live/dev
terragrunt destroy -auto-approve
```

> ⚠️ This destroys all AWS resources (EKS, VPC, NAT Gateways, IAM roles).

## Troubleshooting

```bash
# Nodes not ready
kubectl describe node <node-name>

# Metrics server issues
kubectl logs -n kube-system -l app.kubernetes.io/name=metrics-server

# Autoscaler not scaling
kubectl logs -n kube-system -l app=cluster-autoscaler | tail -30

# Verify OIDC provider (for IRSA)
aws iam list-open-id-connect-providers
```
